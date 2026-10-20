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
