import CoreGraphics
import Foundation
import Testing
@testable import HyperImageCore

struct GIFSpeedTests {
    /// A photo-like noisy gradient: the worst case for palette reduction.
    private func photo(_ w: Int, _ h: Int) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var rng = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: h, by: 4) { for x in stride(from: 0, to: w, by: 4) {
            ctx.setFillColor(CGColor(srgbRed: CGFloat(x) / CGFloat(w), green: CGFloat(y) / CGFloat(h),
                                     blue: CGFloat.random(in: 0...1, using: &rng), alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
        } }
        return try #require(ctx.makeImage())
    }

    @Test func gifOfLargePhotoIsFast() throws {
        // Debug builds run this code far slower, so only release builds get the 24 MP photo.
        #if DEBUG
        let image = try photo(600, 400)
        #else
        let image = try photo(6000, 4000)
        #endif
        var settings = FormatSettings()
        settings.gif.colors = .c256
        let start = Date()
        _ = try ImageEncoder.encode(.init(image: image, sourceProperties: ImageProperties(raw: [:]), sourceJPEGQuality: nil, dpiX: 72, dpiY: 72),
                                    format: .gif, settings: settings)
        let seconds = Date().timeIntervalSince(start)
        #if !DEBUG
        #expect(seconds < 6)
        #endif
    }
}
