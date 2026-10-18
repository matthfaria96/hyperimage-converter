import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Sources in layouts the fixtures do not cover (16-bit, grey, CMYK, alpha, wide gamut) through every output format.
struct UnusualInputTests {
    actor Collector {
        var items: [ConversionRecord] = []
        func add(_ record: ConversionRecord) { items.append(record) }
    }

    static func make(_ space: CGColorSpace, bitsPerComponent: Int, info: UInt32) throws -> CGImage {
        let w = 400, h = 300
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
                                         space: space, bitmapInfo: info))
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(try Fixtures.landscape().image, in: CGRect(x: 50, y: 40, width: 300, height: 220))
        return try #require(ctx.makeImage())
    }

    static func inputs(in dir: URL) throws -> [URL] {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let sources: [(String, CGImage, String)] = [
            ("rgba16.png", try make(srgb, bitsPerComponent: 16,
                                    info: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue), "public.png"),
            ("gray.jpg", try make(CGColorSpaceCreateDeviceGray(), bitsPerComponent: 8, info: CGImageAlphaInfo.none.rawValue), "public.jpeg"),
            ("cmyk.jpg", try make(CGColorSpace(name: CGColorSpace.genericCMYK)!, bitsPerComponent: 8, info: CGImageAlphaInfo.none.rawValue), "public.jpeg"),
            ("alpha.png", try make(srgb, bitsPerComponent: 8, info: CGImageAlphaInfo.premultipliedLast.rawValue), "public.png"),
            ("p3.heic", try make(CGColorSpace(name: CGColorSpace.displayP3)!, bitsPerComponent: 8,
                                 info: CGImageAlphaInfo.noneSkipLast.rawValue), "public.heic"),
        ]
        return try sources.map { name, image, type in
            let url = dir.appendingPathComponent(name)
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            return url
        }
    }

    @Test(arguments: OutputFormat.allCases)
    func everyFormatAcceptsThem(format: OutputFormat) async throws {
        let dir = try TemporaryDirectory()
        let urls = try Self.inputs(in: dir.url)
        var settings = ConvertSettings()
        settings.format = format
        settings.outputFolder = dir.url.appendingPathComponent("out").path
        settings.useAdvancedOptions = true
        settings.advanced.resize.enabled = true
        settings.advanced.text.enabled = true
        settings.advanced.border.enabled = true
        let converter = BatchConverter(settings: settings)
        let collector = Collector()
        try await converter.run(converter.records(for: urls.map { InputItem(url: $0) }),
                                askOverwrite: { _ in .yes }, update: { await collector.add($0) })
        let records = await collector.items
        #expect(records.count == urls.count)
        for record in records {
            #expect(record.status == .done, "\(record.input.lastPathComponent): \(record.status)")
            #expect(ImageLoader.pixelSize(record.output) != nil || format == .pdf)
        }
    }
}
