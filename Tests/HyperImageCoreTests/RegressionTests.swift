import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Regressions found in the 2026-10 review.
struct RegressionTests {
    private func solidImage(space: CGColorSpace, r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat, alphaHalf: Bool = false) throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(colorSpace: space, components: [r, g, b, a])!)
        ctx.fill(CGRect(x: 0, y: 0, width: alphaHalf ? 20 : 40, height: 20))
        return try #require(ctx.makeImage())
    }

    private func encode(_ image: CGImage, _ format: OutputFormat, _ configure: (inout FormatSettings) -> Void) throws -> CGImage {
        var settings = FormatSettings()
        configure(&settings)
        let input = ImageEncoder.Input(image: image, sourceProperties: ImageProperties(raw: [:]),
                                       sourceJPEGQuality: nil, dpiX: 72, dpiY: 72)
        let data = try ImageEncoder.encode(input, format: format, settings: settings)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func palettePNGKeepsTransparency() throws {
        let image = try solidImage(space: CGColorSpace(name: CGColorSpace.sRGB)!, r: 1, g: 0, b: 0, a: 1, alphaHalf: true)
        let out = try encode(image, .png) { $0.png.colors = .c256 }
        #expect(try Fixtures.rgba(out, x: 30, y: 10)[3] == 0)
        #expect(try Fixtures.rgba(out, x: 5, y: 10)[3] == 255)
    }

    @Test func paletteFromDisplayP3StaysAccurate() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = try solidImage(space: p3, r: 0.2, g: 0.6, b: 0.3, a: 1)
        let out = try encode(image, .bmp) { $0.bmp.colors = .c256 }
        let expected = try Fixtures.rgba(encode(image, .png) { _ in }, x: 10, y: 10)
        let got = try Fixtures.rgba(out, x: 10, y: 10)
        for c in 0..<3 { #expect(abs(Int(got[c]) - Int(expected[c])) <= 3) }
    }

    @Test func gpsSecondsNeverPrintSixty() {
        var m = ImageMetadata()
        m.latitude = 12.0 + 34.0 / 60 + 59.97 / 3600
        m.longitude = -(1.0 + 59.0 / 60 + 59.99 / 3600)
        let ctx = TextVariableContext(fileURL: URL(fileURLWithPath: "/a.jpg"), fileDate: Date(),
                                      imageSize: PixelSize(width: 1, height: 1), metadata: m)
        #expect(TextVariables.expand("$GPS2", context: ctx) == "12°35'00.0\"N 2°00'00.0\"W")
    }

    @Test(arguments: [(PaletteSize.c256, 8), (.c16, 4), (.blackWhite, 1)])
    func paletteBMPIsValid(colors: PaletteSize, bits: Int) throws {
        let loaded = try Fixtures.landscape()
        var s = FormatSettings()
        s.bmp.colors = colors
        let data = try ImageEncoder.encode(.init(image: loaded.image, sourceProperties: loaded.properties,
                                                 sourceJPEGQuality: nil, dpiX: 72, dpiY: 72), format: .bmp, settings: s)
        #expect(data.prefix(2) == Data([0x42, 0x4D]))
        #expect(Int(data[28]) == bits)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.pixelSize == PixelSize(width: 1200, height: 800))
    }
}

struct GrayJPEGTests {
    /// The same visible colour in sRGB and Display P3 must give the same gray level.
    @Test func grayFromDisplayP3MatchesSRGB() throws {
        func gray(_ space: CGColorSpace) throws -> UInt8 {
            let ctx = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let color = try #require(CGColor(srgbRed: 0.1, green: 0.7, blue: 0.2, alpha: 1).converted(to: space, intent: .defaultIntent, options: nil))
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            var settings = FormatSettings()
            settings.jpeg.photometric = .grayscale
            settings.jpeg.quality = 100
            let data = try ImageEncoder.encode(.init(image: try #require(ctx.makeImage()), sourceProperties: ImageProperties(raw: [:]),
                                                     sourceJPEGQuality: nil, dpiX: 72, dpiY: 72), format: .jpeg, settings: settings)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return try Fixtures.rgba(image, x: 8, y: 8)[0]
        }
        let a = try gray(CGColorSpace(name: CGColorSpace.sRGB)!)
        let b = try gray(CGColorSpace(name: CGColorSpace.displayP3)!)
        #expect(abs(Int(a) - Int(b)) <= 2)
    }
}
