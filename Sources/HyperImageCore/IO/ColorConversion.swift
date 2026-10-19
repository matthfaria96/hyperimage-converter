import Foundation
import CoreGraphics

/// Builds images in the pixel layouts the encoders need.
enum ColorConversion {
    static func flattened(_ image: CGImage, on color: RGBAColor) throws -> CGImage {
        try renderImage(width: image.width, height: image.height, colorSpace: image.workingColorSpace, flipped: false) { ctx in
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    /// HEIC/AVIF writers reject gray images; redraw those in sRGB (alpha kept).
    static func rgbIfGray(_ image: CGImage) throws -> CGImage {
        guard image.colorSpace?.model == .monochrome else { return image }
        return try renderImage(width: image.width, height: image.height, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, flipped: false) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    static func grayscale(_ image: CGImage) throws -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ImagingError.cannotAllocate(width: w, height: h) }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw ImagingError.cannotAllocate(width: w, height: h) }
        return out
    }

    static func cmyk(_ image: CGImage) throws -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.genericCMYK)!,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ImagingError.cannotAllocate(width: w, height: h) }
        ctx.setFillColor(CGColor(genericCMYKCyan: 0, magenta: 0, yellow: 0, black: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw ImagingError.cannotAllocate(width: w, height: h) }
        return out
    }

    /// Palette image (8 bits per pixel) for PNG/BMP/TIFF, or 1-bit black & white when `colors == 2`.
    static func indexed(_ image: CGImage, colors: Int) throws -> CGImage {
        let quantized = try opaquePalette(image, colors: colors)
        if colors == 2 { return try blackAndWhite(quantized) }
        let table = quantized.palette.flatMap { [$0.r, $0.g, $0.b] }
        guard let space = CGColorSpace(indexedBaseSpace: CGColorSpace(name: CGColorSpace.sRGB)!, last: quantized.palette.count - 1, colorTable: table),
              let provider = CGDataProvider(data: Data(quantized.indices) as CFData),
              let out = CGImage(width: quantized.width, height: quantized.height, bitsPerComponent: 8, bitsPerPixel: 8,
                                bytesPerRow: quantized.width, space: space, bitmapInfo: [], provider: provider,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ImagingError.cannotAllocate(width: image.width, height: image.height)
        }
        return out
    }

    /// Flattens on white and reduces to an sRGB palette.
    static func opaquePalette(_ image: CGImage, colors: Int) throws -> IndexedImage {
        let opaque = try flattened(image, on: .white)
        let bitmap = try Bitmap(image: opaque, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return Quantizer.quantize(bitmap, colors: colors)
    }

    private static func blackAndWhite(_ q: IndexedImage) throws -> CGImage {
        let rowBytes = (q.width + 7) / 8
        var packed = [UInt8](repeating: 0, count: rowBytes * q.height)
        for y in 0..<q.height {
            for x in 0..<q.width where q.indices[y * q.width + x] == 1 {
                packed[y * rowBytes + x / 8] |= 0x80 >> UInt8(x % 8)
            }
        }
        guard let provider = CGDataProvider(data: Data(packed) as CFData),
              let out = CGImage(width: q.width, height: q.height, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ImagingError.cannotAllocate(width: q.width, height: q.height)
        }
        return out
    }
}
