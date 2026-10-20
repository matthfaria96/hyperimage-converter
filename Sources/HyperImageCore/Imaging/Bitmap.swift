import Foundation
import CoreGraphics

/// 8-bit premultiplied RGBA pixels, rows top to bottom with no padding.
public struct Bitmap: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]
    public let colorSpace: CGColorSpace

    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    public init(width: Int, height: Int, pixels: [UInt8], colorSpace: CGColorSpace) {
        precondition(pixels.count == width * height * 4, "pixel buffer does not match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
        self.colorSpace = colorSpace
    }

    public init(width: Int, height: Int, fill: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0), colorSpace: CGColorSpace) {
        let a = fill.alpha
        let px: [UInt8] = [fill.red * a, fill.green * a, fill.blue * a, a].map { UInt8(clamping: Int(($0 * 255).rounded())) }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: buffer.count, by: 4) {
            buffer[i] = px[0]; buffer[i + 1] = px[1]; buffer[i + 2] = px[2]; buffer[i + 3] = px[3]
        }
        self.init(width: width, height: height, pixels: buffer, colorSpace: colorSpace)
    }

    public init(image: CGImage, colorSpace: CGColorSpace) throws {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: try Bitmap.checkedByteCount(width: width, height: height))
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImagingError.cannotAllocate(width: width, height: height) }
        self.init(width: width, height: height, pixels: buffer, colorSpace: colorSpace)
    }

    /// Bytes needed for a `width` × `height` RGBA buffer; throws instead of overflowing or exceeding `SafeLimits.maxPixels`.
    /// Only the total area is capped, so wide panoramas within 400 MP still decode.
    public static func checkedByteCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else { throw ImagingError.cannotAllocate(width: width, height: height) }
        let (area, areaOverflow) = width.multipliedReportingOverflow(by: height)
        guard !areaOverflow, area <= SafeLimits.maxPixels else { throw ImagingError.cannotAllocate(width: width, height: height) }
        let (bytes, byteOverflow) = area.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else { throw ImagingError.cannotAllocate(width: width, height: height) }
        return bytes
    }

    public var size: PixelSize { PixelSize(width: width, height: height) }

    public func makeImage() throws -> CGImage {
        var copy = pixels
        let image = copy.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: Bitmap.bitmapInfo)?.makeImage()
        }
        guard let image else { throw ImagingError.cannotAllocate(width: width, height: height) }
        return image
    }

    /// True when every pixel is fully opaque.
    public var isOpaque: Bool {
        pixels.withUnsafeBufferPointer { p in
            var i = 3
            while i < p.count {
                if p[i] != 255 { return false }
                i += 4
            }
            return true
        }
    }
}

public enum ImagingError: LocalizedError, Equatable {
    case cannotAllocate(width: Int, height: Int)
    case unreadable(String)
    case encodeFailed(String)
    case watermarkMissing(String)

    public var errorDescription: String? {
        switch self {
        case let .cannotAllocate(w, h): String(localized: "Memória insuficiente para uma imagem de \(w) × \(h).")
        case let .unreadable(name): String(localized: "Não foi possível ler \(name).")
        case let .encodeFailed(format): String(localized: "Falha ao gravar no formato \(format).")
        case let .watermarkMissing(path): String(localized: "Imagem da marca d'água não encontrada: \(path)")
        }
    }
}

