import CJPEG
import CoreGraphics
import Foundation

/// JPEG writing and lossless cropping through the vendored IJG libjpeg.
enum LibJPEG {
    struct Options {
        var quality: Int
        var colorSpace: HIJColorSpace
        var subsampling: JPEGSubsampling
        var smoothing: Int
        var optimizeHuffman: Bool
        var progressive: Bool
        var dpiX: Double
        var dpiY: Double
    }

    static func encode(_ image: CGImage, options: Options) throws -> Data {
        // Keep the image's own RGB space (Display P3, Adobe RGB...) and tag it, so wide-gamut photos are not clipped.
        // Gray output carries no profile, so its luminance must be computed from sRGB values, not P3 ones.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = options.colorSpace == HIJ_GRAY ? srgb
            : image.colorSpace.flatMap { $0.model == .rgb && $0.copyICCData() != nil ? $0 : nil } ?? srgb
        let bitmap = try Bitmap(image: image, colorSpace: space)
        let icc = options.colorSpace == HIJ_GRAY ? nil : space.copyICCData() as Data?
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = bitmap.pixels.withUnsafeBufferPointer { pixels in
            withICC(icc) { iccPointer, iccLength in
                var raw = HIJEncodeOptions(
                    quality: Int32(min(100, max(0, options.quality))),
                    colorSpace: options.colorSpace,
                    subsampling: options.subsampling.native,
                    smoothing: Int32(options.smoothing.clamped(to: JPEGSettings.smoothingRange)),
                    optimizeHuffman: options.optimizeHuffman ? 1 : 0,
                    progressive: options.progressive ? 1 : 0,
                    dpiX: options.dpiX, dpiY: options.dpiY,
                    icc: iccPointer, iccLength: iccLength)
                return hij_encode_rgba(pixels.baseAddress, Int32(bitmap.width), Int32(bitmap.height),
                                       bitmap.width * 4, &raw, &output, &length)
            }
        }
        return try take(status, output, length)
    }

    /// The cropped file, or nil when the rectangle is not on the source's block grid (re-encode instead).
    static func losslessCrop(_ jpeg: Data, rect: PixelRect, keepMarkers: Bool, progressive: Bool,
                             dpiX: Double, dpiY: Double) throws -> Data? {
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = jpeg.withUnsafeBytes { bytes in
            hij_lossless_crop(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count,
                              Int32(rect.x), Int32(rect.y), Int32(rect.width), Int32(rect.height),
                              keepMarkers ? 1 : 0, progressive ? 1 : 0, dpiX, dpiY, &output, &length)
        }
        if status == HIJ_UNALIGNED { return nil }
        return try take(status, output, length)
    }

    private static func withICC<T>(_ icc: Data?, _ body: (UnsafePointer<UInt8>?, Int) -> T) -> T {
        guard let icc else { return body(nil, 0) }
        return icc.withUnsafeBytes { body($0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
    }

    private static func take(_ status: HIJStatus, _ output: UnsafeMutablePointer<UInt8>?, _ length: Int) throws -> Data {
        guard status == HIJ_OK, let output else { throw ImagingError.encodeFailed("JPEG") }
        defer { hij_free(output) }
        return Data(bytes: output, count: length)
    }
}

private extension JPEGSubsampling {
    var native: HIJSubsampling {
        switch self {
        case .none: HIJ_SUB_NONE
        case .medium: HIJ_SUB_MEDIUM
        case .high: HIJ_SUB_HIGH
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
