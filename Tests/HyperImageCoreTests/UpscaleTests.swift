import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Runs against Vendor/Upscayl (scripts/fetch-upscayl.sh); skipped when the backend has not been downloaded.
struct UpscaleTests {
    static let vendor = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Vendor/Upscayl")
    static var available: Bool { FileManager.default.isExecutableFile(atPath: vendor.appendingPathComponent("upscayl-bin").path) }
    static var upscaler: Upscaler {
        Upscaler(executable: vendor.appendingPathComponent("upscayl-bin"), modelsFolder: vendor.appendingPathComponent("models"))
    }

    @Test func namesCarryScaleAndFormat() {
        var s = ConvertSettings()
        s.mode = .upscale
        s.useOutputFolder = false
        s.upscale.scale = 2
        s.upscale.format = .webp
        let out = OutputPlanner.destinations(for: [InputItem(url: URL(fileURLWithPath: "/f/foto.heic"))], settings: s)
        #expect(out.map(\.path) == ["/f/foto-upscale-2x.webp"])
    }

    @Test(.enabled(if: UpscaleTests.available))
    func batchUpscalesEveryModelAndOddInput() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("up-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A small TIFF exercises the temporary-PNG path.
        let fixture = try #require(Bundle.module.url(forResource: "retrato", withExtension: "jpg", subdirectory: "Fixtures"))
        let loaded = try ImageLoader.load(fixture)
        let small = dir.appendingPathComponent("pequena.tif")
        let ctx = try #require(CGContext(data: nil, width: 60, height: 90, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(loaded.image, in: CGRect(x: 0, y: 0, width: 60, height: 90))
        let dest = try #require(CGImageDestinationCreateWithURL(small as CFURL, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))

        for model in UpscaleModel.allCases {
            var s = ConvertSettings()
            s.mode = .upscale
            s.outputFolder = dir.appendingPathComponent(model.rawValue).path
            s.upscale.model = model
            s.upscale.scale = 3
            let converter = BatchConverter(settings: s, upscaler: Self.upscaler)
            let records = converter.records(for: [InputItem(url: small)])
            let results = Results()
            try await converter.run(records, askOverwrite: { _ in .yes }, update: { await results.set($0) })
            let final = try #require(await results.last)
            #expect(final.status == .done, "\(model): \(final.status)")
            #expect(ImageLoader.pixelSize(final.output) == PixelSize(width: 180, height: 270))
        }
    }

    @Test func missingBackendFailsClearly() async throws {
        var s = ConvertSettings()
        s.mode = .upscale
        s.useOutputFolder = false
        let converter = BatchConverter(settings: s, upscaler: nil)
        let records = converter.records(for: [InputItem(url: URL(fileURLWithPath: "/tmp/nada.png"))])
        let results = Results()
        try await converter.run(records, askOverwrite: { _ in .yes }, update: { await results.set($0) })
        guard case .failed = try #require(await results.last).status else { Issue.record("expected failure"); return }
    }

    private actor Results {
        var last: ConversionRecord?
        func set(_ r: ConversionRecord) { last = r }
    }
}

struct UpscaleProgressParsingTests {
    @Test func parsesBackendPercentages() {
        #expect(Upscaler.percentage("42.50%") == 42.5)
        #expect(Upscaler.percentage(" 100.00 ") == 100)
        #expect(Upscaler.percentage("🙌 Upscayled Successfully!") == nil)
        #expect(Upscaler.percentage("140%") == nil)
    }
}
