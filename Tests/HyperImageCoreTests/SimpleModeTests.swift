import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// The simplified window's options: compress mode, size target, dimension limit, transparency, suffix, skip.
struct SimpleModeTests {
    /// Folders handed out here are removed when the suite instance (one per test) goes away.
    private let scratch = try! TemporaryDirectory()

    private func tempDir() throws -> URL { scratch.url }

    private func copyFixture(_ name: String, to dir: URL) throws -> URL {
        let source = try #require(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"))
        let target = dir.appendingPathComponent("\(name).jpg")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    private func writePNG(_ dir: URL, name: String, transparent: Bool) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: transparent ? 100 : 200, height: 100))
        let url = dir.appendingPathComponent(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func run(_ settings: ConvertSettings, _ items: [URL]) async throws -> [ConversionRecord] {
        let converter = BatchConverter(settings: settings)
        let records = converter.records(for: items.map { InputItem(url: $0) })
        let collected = Collected()
        try await converter.run(records, askOverwrite: { _ in .cancel }, update: { await collected.add($0) })
        return await collected.latest.values.sorted { $0.id < $1.id }
    }

    private actor Collected {
        var latest: [Int: ConversionRecord] = [:]
        func add(_ r: ConversionRecord) { latest[r.id] = r }
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func compressKeepsEachFormatAndAddsSuffix() throws {
        var s = ConvertSettings()
        s.mode = .compress
        s.useOutputFolder = false
        s.addSuffix = true
        let items = [URL(fileURLWithPath: "/f/a.png"), URL(fileURLWithPath: "/f/b.JPG"), URL(fileURLWithPath: "/f/c.psd")]
        let names = OutputPlanner.destinations(for: items.map { InputItem(url: $0) }, settings: s).map(\.lastPathComponent)
        #expect(names == ["a-comprimido.png", "b-comprimido.jpg", "c-comprimido.jpg"])
        s.mode = .convert
        s.format = .webp
        s.addSuffix = false
        #expect(OutputPlanner.destinations(for: [InputItem(url: items[0])], settings: s).map(\.lastPathComponent) == ["a.webp"])
    }

    @Test func fileSizeTargetIsMet() async throws {
        let dir = try tempDir()
        let input = try copyFixture("paisagem", to: dir)
        var s = ConvertSettings()
        s.outputFolder = dir.appendingPathComponent("out").path
        s.formatSettings.jpeg.quality = 100
        s.limitFileSize = true
        s.maxFileSizeKB = 20
        let records = try await run(s, [input])
        #expect(records.first?.status == .done)
        #expect(try #require(records.first).newSize <= 20 * 1024)
        #expect(try #require(records.first).newSize > 5 * 1024)
    }

    @Test func dimensionLimitShrinksOnlyLargeImages() async throws {
        let dir = try tempDir()
        let input = try copyFixture("paisagem", to: dir) // 1200 × 800
        var s = ConvertSettings()
        s.outputFolder = dir.appendingPathComponent("out").path
        s.keepDimensions = false
        s.maxLongSide = 600
        let records = try await run(s, [input])
        #expect(try decode(try #require(records.first).output).width == 600)
        s.maxLongSide = 5000
        s.addSuffix = true
        let again = try await run(s, [input])
        #expect(try decode(try #require(again.first).output).width == 1200)
    }

    @Test func transparencyCanBeFlattened() async throws {
        let dir = try tempDir()
        let input = try writePNG(dir, name: "logo.png", transparent: true)
        var s = ConvertSettings()
        s.outputFolder = dir.appendingPathComponent("out").path
        s.format = .png
        s.preserveTransparency = false
        let out = try decode(try #require(try await run(s, [input]).first).output)
        #expect(try Fixtures.rgba(out, x: 150, y: 50) == [255, 255, 255, 255])
        s.preserveTransparency = true
        s.addSuffix = true
        let kept = try decode(try #require(try await run(s, [input]).first).output)
        #expect(try Fixtures.rgba(kept, x: 150, y: 50)[3] == 0)
    }

    @Test func skipExistingLeavesFilesAlone() async throws {
        let dir = try tempDir()
        let input = try copyFixture("retrato", to: dir)
        var s = ConvertSettings()
        s.outputFolder = dir.appendingPathComponent("out").path
        s.askBeforeOverwrite = false
        s.skipExisting = true
        let target = try #require(BatchConverter(settings: s).records(for: [InputItem(url: input)]).first).output
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("antigo".utf8).write(to: target)
        let records = try await run(s, [input])
        #expect(records.first?.status == .skipped)
        #expect(try Data(contentsOf: target) == Data("antigo".utf8))
    }
}
