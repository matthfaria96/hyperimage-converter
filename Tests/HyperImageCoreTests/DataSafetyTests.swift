import Foundation
import Testing
@testable import HyperImageCore

/// SAFE-01..03: originals are never overwritten and upscale temp files never leak.
struct DataSafetyTests {
    private static func key(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }

    private static func inPlace(_ mode: ConvertMode = .compress) -> ConvertSettings {
        var s = ConvertSettings()
        s.mode = mode
        s.useOutputFolder = false
        s.addSuffix = false
        return s
    }

    @Test func compressWithoutSuffixNeverTargetsTheInput() {
        let input = URL(fileURLWithPath: "/f/a.png")
        let out = OutputPlanner.destinations(for: [InputItem(url: input)], settings: Self.inPlace())
        #expect(Self.key(out[0]) != Self.key(input))
        #expect(out[0].path == "/f/a-2.png")
    }

    @Test func convertToSameFormatNeverTargetsTheInput() {
        var s = Self.inPlace(.convert)
        s.format = .png
        let input = URL(fileURLWithPath: "/f/a.png")
        let out = OutputPlanner.destinations(for: [InputItem(url: input)], settings: s)
        #expect(out[0].path == "/f/a-2.png")
    }

    @Test func extensionCaseDoesNotBypassTheCheck() {
        for upper in [false, true] {
            var s = Self.inPlace()
            s.uppercaseExtension = upper
            let inputs = [URL(fileURLWithPath: "/f/b.JPG"), URL(fileURLWithPath: "/f/c.jpg")]
            let out = OutputPlanner.destinations(for: inputs.map { InputItem(url: $0) }, settings: s)
            let inputKeys = Set(inputs.map(Self.key))
            for url in out { #expect(!inputKeys.contains(Self.key(url))) }
        }
    }

    @Test func neighbouringNumberedInputsStayUntouchedAndUnique() {
        let inputs = [URL(fileURLWithPath: "/f/a.png"), URL(fileURLWithPath: "/f/a-2.png")]
        let out = OutputPlanner.destinations(for: inputs.map { InputItem(url: $0) }, settings: Self.inPlace())
        let inputKeys = Set(inputs.map(Self.key))
        for url in out { #expect(!inputKeys.contains(Self.key(url))) }
        #expect(Set(out.map(Self.key)).count == out.count)
    }

    @Test func differentFormatKeepsPlainName() {
        var s = Self.inPlace(.convert)
        s.format = .jpeg
        let out = OutputPlanner.destinations(for: [InputItem(url: URL(fileURLWithPath: "/f/a.png"))], settings: s)
        #expect(out.map(\.lastPathComponent) == ["a.jpg"])
    }
}

/// SAFE-03: upscale temp directories are removed on every exit; existing outputs are swapped atomically.
@Suite(.serialized)
struct UpscaleCleanupTests {
    private static func leftovers() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("hyperimage-upscale-") })
    }

    private static func backend(in dir: URL, exitCode: Int) throws -> URL {
        let script = dir.appendingPathComponent("fake-upscayl")
        let body = """
        #!/bin/sh
        while [ $# -gt 0 ]; do
          case "$1" in -i) IN="$2"; shift 2;; -o) OUT="$2"; shift 2;; *) shift;; esac
        done
        [ \(exitCode) -ne 0 ] && exit \(exitCode)
        cp "$IN" "$OUT"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test func missingBackendLeavesNoTempDir() async throws {
        let scratch = try TemporaryDirectory()
        let before = Self.leftovers()
        let upscaler = Upscaler(executable: scratch.url.appendingPathComponent("absent"), modelsFolder: scratch.url)
        await #expect(throws: UpscaleError.self) {
            try await upscaler.upscale(Fixtures.url("retrato"), to: scratch.url.appendingPathComponent("out.png"), settings: UpscaleSettings())
        }
        #expect(Self.leftovers().subtracting(before).isEmpty)
    }

    @Test func cancelledUpscaleLeavesNoTempDir() async throws {
        let scratch = try TemporaryDirectory()
        let before = Self.leftovers()
        let script = try Self.backend(in: scratch.url, exitCode: 0)
        let upscaler = Upscaler(executable: script, modelsFolder: scratch.url)
        let output = scratch.url.appendingPathComponent("out.png")
        let task = Task {
            try await upscaler.upscale(Fixtures.url("paisagem"), to: output, settings: UpscaleSettings())
        }
        task.cancel()
        _ = await task.result
        #expect(Self.leftovers().subtracting(before).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func successReplacesExistingOutputAndCleansUp() async throws {
        let scratch = try TemporaryDirectory()
        let before = Self.leftovers()
        let script = try Self.backend(in: scratch.url, exitCode: 0)
        let output = scratch.url.appendingPathComponent("out.png")
        try Data("old".utf8).write(to: output)
        let upscaler = Upscaler(executable: script, modelsFolder: scratch.url)
        try await upscaler.upscale(Fixtures.url("paisagem"), to: output, settings: UpscaleSettings())
        #expect(try Data(contentsOf: output) == Data(contentsOf: Fixtures.url("paisagem")))
        #expect(Self.leftovers().subtracting(before).isEmpty)
    }

    @Test func failingBackendKeepsExistingOutput() async throws {
        let scratch = try TemporaryDirectory()
        let before = Self.leftovers()
        let script = try Self.backend(in: scratch.url, exitCode: 1)
        let output = scratch.url.appendingPathComponent("out.png")
        try Data("old".utf8).write(to: output)
        let upscaler = Upscaler(executable: script, modelsFolder: scratch.url)
        await #expect(throws: (any Error).self) {
            try await upscaler.upscale(Fixtures.url("paisagem"), to: output, settings: UpscaleSettings())
        }
        #expect(try Data(contentsOf: output) == Data("old".utf8))
        #expect(Self.leftovers().subtracting(before).isEmpty)
    }
}
