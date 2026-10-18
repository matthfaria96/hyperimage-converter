import CoreGraphics
import Foundation
import ImageIO

/// One page sized to the image (at its DPI or 72 dpi) with the image embedded as JPEG, Flate or 1-bit.
enum PDFEncoder {
    static func encode(_ image: CGImage, settings: PDFSettings, dpi: Double) throws -> Data {
        let embedded = try embeddedImage(image, quality: settings.quality)
        let scale = 72 / (settings.useOriginalDPI ? max(1, dpi) : 72)
        var box = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ImagingError.encodeFailed("PDF") }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(embedded, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func embeddedImage(_ image: CGImage, quality: PDFQuality) throws -> CGImage {
        switch quality {
        case .lossless:
            return image
        case .blackWhite:
            return try ColorConversion.indexed(image, colors: 2)
        default:
            // Pre-compress so Quartz embeds the JPEG stream (DCTDecode) instead of re-encoding losslessly.
            let flat = try ColorConversion.flattened(image, on: .white)
            let jpeg = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil) else {
                throw ImagingError.encodeFailed("PDF")
            }
            CGImageDestinationAddImage(dest, flat, [kCGImageDestinationLossyCompressionQuality: Double(quality.rawValue) / 100] as CFDictionary)
            guard CGImageDestinationFinalize(dest),
                  let provider = CGDataProvider(data: jpeg),
                  let decoded = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                throw ImagingError.encodeFailed("PDF")
            }
            return decoded
        }
    }
}
