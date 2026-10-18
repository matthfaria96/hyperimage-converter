import CoreGraphics
import CWebP
import Foundation

/// Lossy/lossless WebP through the vendored libwebp (ImageIO can read WebP but not write it).
enum WebPEncoder {
    static func encode(_ image: CGImage, settings: WebPSettings) throws -> Data {
        let rgba = try straightRGBA(image)
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw ImagingError.encodeFailed("WebP") }
        if settings.lossless {
            guard WebPConfigLosslessPreset(&config, 6) != 0 else { throw ImagingError.encodeFailed("WebP") }
        } else {
            config.quality = Float(settings.quality)
            config.method = 4
            config.use_sharp_yuv = settings.sharpYUV ? 1 : 0
        }
        config.thread_level = 1

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw ImagingError.encodeFailed("WebP") }
        defer { WebPPictureFree(&picture) }
        picture.use_argb = settings.lossless ? 1 : 0
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        let imported = rgba.withUnsafeBufferPointer {
            WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(image.width * 4))
        }
        guard imported != 0 else { throw ImagingError.encodeFailed("WebP") }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        try withUnsafeMutablePointer(to: &writer) { writerPointer in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(writerPointer)
            guard WebPEncode(&config, &picture) != 0 else { throw ImagingError.encodeFailed("WebP") }
        }
        return Data(bytes: writer.mem, count: writer.size)
    }

    /// Un-premultiplied sRGB RGBA, which is what libwebp expects.
    private static func straightRGBA(_ image: CGImage) throws -> [UInt8] {
        var bitmap = try Bitmap(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!).pixels
        for i in stride(from: 0, to: bitmap.count, by: 4) {
            let a = Int(bitmap[i + 3])
            guard a != 0 && a != 255 else { continue }
            for c in 0..<3 { bitmap[i + c] = UInt8(min(255, (Int(bitmap[i + c]) * 255 + a / 2) / a)) }
        }
        return bitmap
    }
}
