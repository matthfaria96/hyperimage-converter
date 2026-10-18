import CoreGraphics
import Foundation
import ImageIO

/// Turns a processed image into file bytes for the chosen output format.
public enum ImageEncoder {
    public struct Input: @unchecked Sendable {
        public var image: CGImage
        public var sourceProperties: ImageProperties
        public var sourceJPEGQuality: Int?
        /// DPI to record in the output (the source's, unless the DPI step changed it).
        public var dpiX: Double
        public var dpiY: Double

        public init(image: CGImage, sourceProperties: ImageProperties, sourceJPEGQuality: Int?, dpiX: Double, dpiY: Double) {
            self.image = image
            self.sourceProperties = sourceProperties
            self.sourceJPEGQuality = sourceJPEGQuality
            self.dpiX = dpiX
            self.dpiY = dpiY
        }
    }

    public static func encode(_ input: Input, format: OutputFormat, settings: FormatSettings) throws -> Data {
        switch format {
        case .webp: return try WebPEncoder.encode(input.image, settings: settings.webp)
        case .pdf: return try PDFEncoder.encode(input.image, settings: settings.pdf, dpi: input.dpiX)
        default: break
        }
        let (image, options) = try prepare(input, format: format, settings: settings)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ImagingError.encodeFailed(format.displayName)
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImagingError.encodeFailed(format.displayName) }
        return data as Data
    }

    private static func prepare(_ input: Input, format: OutputFormat, settings: FormatSettings) throws -> (CGImage, [CFString: Any]) {
        var options: [CFString: Any] = [
            kCGImagePropertyDPIWidth: input.dpiX,
            kCGImagePropertyDPIHeight: input.dpiY,
            kCGImagePropertyOrientation: 1,
        ]
        var image = input.image
        switch format {
        case .jpeg:
            let s = settings.jpeg
            if s.keepMetadata { options = carriedMetadata(input.sourceProperties).merging(options) { _, new in new } }
            let quality = s.useOriginalQuality ? (input.sourceJPEGQuality ?? s.quality) : s.quality
            options[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100
            if s.progressive { options[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true] }
            image = try ColorConversion.flattened(image, on: .white)
            switch s.photometric {
            case .grayscale: image = try ColorConversion.grayscale(image)
            case .cmyk: image = try ColorConversion.cmyk(image)
            case .noChange, .rgb, .ycbcr: break
            }
        case .bmp:
            image = try paletted(image, colors: settings.bmp.colors.colorCount, flatten: true)
        case .gif:
            image = try gifReady(image, settings: settings.gif)
        case .png:
            image = try paletted(image, colors: settings.png.colors.colorCount, flatten: false)
            if settings.png.interlaced { options[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGInterlaceType: 1] }
        case .jpeg2000:
            let s = settings.jpeg2000
            options[kCGImageDestinationLossyCompressionQuality] = Double(s.quality) / 100
            if s.photometric == .grayscale { image = try ColorConversion.grayscale(image) }
        case .tiff:
            let s = settings.tiff
            options[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: s.compression.tagValue]
            switch s.photometric {
            case .grayscale: image = try ColorConversion.grayscale(image)
            case .cmyk: image = try ColorConversion.cmyk(image)
            case .palette256: image = try ColorConversion.indexed(image, colors: 256)
            case .noChange, .rgb: break
            }
        case .heic:
            options[kCGImageDestinationLossyCompressionQuality] = Double(settings.heic.quality) / 100
            if settings.heic.keepMetadata { options = carriedMetadata(input.sourceProperties).merging(options) { _, new in new } }
        case .avif:
            options[kCGImageDestinationLossyCompressionQuality] = Double(settings.avif.quality) / 100
        case .webp, .pdf:
            break
        }
        return (image, options)
    }

    private static func paletted(_ image: CGImage, colors: Int?, flatten: Bool) throws -> CGImage {
        guard let colors else { return flatten ? try ColorConversion.flattened(image, on: .white) : image }
        return try ColorConversion.indexed(image, colors: colors)
    }

    /// GIF: reduce to the palette ourselves (so the colour count is honoured) and keep or drop transparency.
    private static func gifReady(_ image: CGImage, settings: GIFSettings) throws -> CGImage {
        let base = settings.transparent ? image : try ColorConversion.flattened(image, on: .white)
        let bitmap = try Bitmap(image: base, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let quantized = Quantizer.quantize(bitmap, colors: settings.colors.colorCount ?? 256, keepTransparency: settings.transparent)
        return try Quantizer.expand(quantized, like: bitmap).makeImage()
    }

    /// EXIF/IPTC/GPS/TIFF dictionaries to copy into the output (orientation is reset since pixels are upright).
    private static func carriedMetadata(_ properties: ImageProperties) -> [CFString: Any] {
        let keys = [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary]
        var out: [CFString: Any] = [:]
        for key in keys { if let value = properties.raw[key] { out[key] = value } }
        if var exif = out[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            out[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = out[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        return out
    }
}
