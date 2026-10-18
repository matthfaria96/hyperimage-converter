import CoreGraphics
import Foundation
import ImageIO

/// A converted file's bytes and the pixel size they hold.
public struct EncodedOutput: @unchecked Sendable {
    public let data: Data
    public let pixelSize: PixelSize
    /// The processed pixels, when the output was re-encoded from them (nil for a lossless crop).
    public let image: CGImage?
}

extension ImagePipeline {
    /// Processes and encodes one file, cutting JPEG blocks directly when lossless cropping applies.
    public func encode(_ loaded: LoadedImage, format: OutputFormat, settings: FormatSettings) throws -> EncodedOutput {
        if let rect = losslessCropRect(loaded, format: format, settings: settings.jpeg),
           let data = try losslessCrop(loaded, rect: rect, settings: settings.jpeg) {
            return EncodedOutput(data: data, pixelSize: PixelSize(width: rect.width, height: rect.height), image: nil)
        }
        let processed = try process(loaded)
        let data = try ImageEncoder.encode(
            .init(image: processed.image, sourceProperties: loaded.properties, sourceJPEGQuality: loaded.metadata.jpegQuality,
                  dpiX: processed.dpiX, dpiY: processed.dpiY),
            format: format, settings: settings)
        return EncodedOutput(data: data, pixelSize: processed.image.pixelSize, image: processed.image)
    }

    /// "Lossless Crop for JPEG format if possible": when cropping is the only step that changes pixels and the
    /// source is an upright JPEG going out as JPEG, cut its DCT blocks directly instead of re-encoding.
    /// Returns nil whenever that is not possible, and the caller converts normally.
    func losslessCrop(_ source: LoadedImage, rect: PixelRect, settings: JPEGSettings) throws -> Data? {
        let data = try Data(contentsOf: source.url, options: .mappedIfSafe)
        let dpi = options.dpi.enabled ? (options.dpi.x, options.dpi.y) : (source.metadata.dpiX ?? 0, source.metadata.dpiY ?? 0)
        return try LibJPEG.losslessCrop(data, rect: rect, keepMarkers: settings.keepMetadata, progressive: settings.progressive,
                                        dpiX: dpi.0, dpiY: dpi.1)
    }

    func losslessCropRect(_ source: LoadedImage, format: OutputFormat, settings: JPEGSettings) -> PixelRect? {
        let o = options
        let orientation = source.properties.raw[kCGImagePropertyOrientation] as? Int ?? 1
        let colorModel = source.properties.raw[kCGImagePropertyColorModel] as? String
        guard o.crop.enabled, o.crop.losslessJPEG, format == .jpeg, source.sourceType == "public.jpeg", orientation == 1,
              settings.photometric == .noChange || (settings.photometric == .ycbcr && colorModel == "RGB"),
              onlyCropTouchesPixels else { return nil }
        let rect = CropGeometry.rect(source: source.image.pixelSize, options: o.crop, sourceDPI: source.dpi, jpegBlock: 16)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    private var onlyCropTouchesPixels: Bool {
        let o = options
        let rotates = o.rotate.isEffective
        let adjusts = o.adjustments.enabled && !o.adjustments.isIdentity
        let reducesColors = o.colorDepth.enabled && o.colorDepth.depth.colorCount != nil
        return !(o.resize.enabled || rotates || o.canvas.enabled || adjusts || reducesColors
                 || o.text.enabled || o.watermark.enabled || o.border.enabled)
    }
}
