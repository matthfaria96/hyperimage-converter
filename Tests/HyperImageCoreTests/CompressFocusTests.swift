import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Comprimir's promises: metadata stripped by default, a truly lossless level, never a bigger file,
/// and no silent format change for files it cannot write back.
struct CompressFocusTests {
    private let scratch = try! TemporaryDirectory()

    private func fixture(_ name: String) throws -> URL {
        let source = try #require(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"))
        let target = scratch.url.appendingPathComponent("\(name).jpg")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    /// A JPEG carrying a GPS position, like an iPhone photo.
    private func jpegWithGPS() throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        let url = scratch.url.appendingPathComponent("gps.jpg")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 23.5, kCGImagePropertyGPSLatitudeRef: "S",
                                    kCGImagePropertyGPSLongitude: 46.6, kCGImagePropertyGPSLongitudeRef: "W"]
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()),
                                   [kCGImagePropertyGPSDictionary: gps, kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func compress(_ url: URL, _ change: (inout ConvertSettings) -> Void = { _ in }) throws -> Data {
        var s = ConvertSettings()
        s.mode = .compress
        change(&s)
        let pipeline = try ImagePipeline(options: s.effectiveAdvancedOptions)
        return try OutputEncoder.encode(try ImageLoader.load(url), pipeline: pipeline, settings: s).data
    }

    private func hasGPS(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return props[kCGImagePropertyGPSDictionary] != nil
    }

    private func pixels(_ data: Data) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bitmap = try Bitmap(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return Array(bitmap.pixels)
    }

    @Test func metadataIsStrippedByDefault() throws {
        let url = try jpegWithGPS()
        #expect(hasGPS(try Data(contentsOf: url)))
        #expect(!hasGPS(try compress(url) { $0.compressQuality = CompressionLevel.strong.quality }))
        #expect(hasGPS(try compress(url) { $0.compressQuality = CompressionLevel.strong.quality; $0.stripMetadata = false }))
    }

    @Test func losslessLevelKeepsEveryPixel() throws {
        let url = try fixture("paisagem")
        let original = try Data(contentsOf: url)
        let out = try compress(url) { $0.compressQuality = CompressionLevel.lossless.quality }
        #expect(out.count <= original.count)
        #expect(try pixels(out) == pixels(original))
    }

    /// Even when compressing gains nothing, the location must not come back with the original bytes.
    @Test func strippingWinsOverKeepingTheOriginal() throws {
        let url = try jpegWithGPS()
        let out = try compress(url) { $0.compressQuality = 99 }
        #expect(!hasGPS(out))
        #expect(out.count <= (try Data(contentsOf: url)).count)
    }

    @Test func neverReturnsABiggerFile() throws {
        let url = try fixture("retrato")
        let size = try Data(contentsOf: url).count
        // Quality 99 re-encodes a JPEG into something larger; the original must come back instead.
        let out = try compress(url) { $0.compressQuality = 99; $0.stripMetadata = false }
        #expect(out.count <= size)
    }

    @Test func unwritableFormatIsReportedNotConverted() async throws {
        let psd = scratch.url.appendingPathComponent("camada.psd")
        try FileManager.default.copyItem(at: try fixture("paisagem"), to: psd)
        var s = ConvertSettings()
        s.mode = .compress
        s.outputFolder = scratch.url.appendingPathComponent("out").path
        let converter = BatchConverter(settings: s)
        let record = try #require(converter.records(for: [InputItem(url: psd)]).first)
        let result = converter.convert(record, pipeline: try ImagePipeline(options: AdvancedOptions()))
        guard case let .failed(message) = result.status else { Issue.record("expected a failure"); return }
        #expect(message.contains("PSD"))
        #expect(!FileManager.default.fileExists(atPath: record.output.path))
    }
}
