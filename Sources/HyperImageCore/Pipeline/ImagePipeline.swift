import CoreGraphics
import Foundation

public struct ProcessedImage: @unchecked Sendable {
    public let image: CGImage
    public let dpiX: Double
    public let dpiY: Double
}

/// Runs the enabled Advanced Options steps in the original app's order:
/// adjustments (if before) → resize → flip/rotate → crop → canvas → adjustments → colour depth → DPI → text → watermark → border.
public struct ImagePipeline: @unchecked Sendable {
    public let options: AdvancedOptions
    private let watermark: CGImage?

    public init(options: AdvancedOptions) throws {
        self.options = options
        if options.watermark.enabled {
            let url = URL(fileURLWithPath: (options.watermark.imagePath as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ImagingError.watermarkMissing(options.watermark.imagePath)
            }
            watermark = try ImageLoader.load(url).image
        } else {
            watermark = nil
        }
    }

    public func process(_ source: LoadedImage) throws -> ProcessedImage {
        let o = options
        var image = source.image
        let adjust = o.adjustments.enabled && !o.adjustments.isIdentity

        if adjust && o.adjustments.beforeResize { image = try ColorAdjuster.apply(o.adjustments, to: image) }
        if o.resize.enabled, let plan = ResizeGeometry.plan(source: image.pixelSize, options: o.resize, sourceDPI: source.dpi) {
            image = try Transforms.resize(image, plan: plan, filter: o.resize.filter, fill: o.resize.fillColor)
        }
        if o.rotate.enabled && (o.rotate.rotate || o.rotate.flipHorizontal || o.rotate.flipVertical) {
            image = try Transforms.flipRotate(image, options: o.rotate)
        }
        if o.crop.enabled {
            // Block alignment only means something while the pixels are still the JPEG's own grid.
            let untouched = image.pixelSize == source.image.pixelSize && !(o.resize.enabled || o.rotate.enabled || (adjust && o.adjustments.beforeResize))
            let block = source.sourceType == "public.jpeg" && untouched ? 16 : nil
            image = try Transforms.crop(image, to: CropGeometry.rect(source: image.pixelSize, options: o.crop, sourceDPI: source.dpi, jpegBlock: block))
        }
        if o.canvas.enabled {
            image = try Transforms.canvas(image, plan: CanvasGeometry.plan(source: image.pixelSize, options: o.canvas), background: o.canvas.background)
        }
        if adjust && !o.adjustments.beforeResize { image = try ColorAdjuster.apply(o.adjustments, to: image) }
        if o.colorDepth.enabled, let count = o.colorDepth.depth.colorCount {
            image = try Transforms.reduceColors(image, count: count)
        }
        if o.text.enabled {
            let context = TextVariableContext(fileURL: source.url, fileDate: source.modificationDate,
                                              imageSize: image.pixelSize, metadata: source.metadata)
            image = try TextOverlay.apply(TextVariables.expand(o.text.text, context: context), options: o.text, to: image)
        }
        if let watermark, o.watermark.enabled {
            image = try WatermarkOverlay.apply(watermark, options: o.watermark, to: image)
        }
        if o.border.enabled { image = try BorderEffect.apply(o.border, to: image) }

        let dpiX = o.dpi.enabled ? o.dpi.x : (source.metadata.dpiX ?? 72)
        let dpiY = o.dpi.enabled ? o.dpi.y : (source.metadata.dpiY ?? dpiX)
        return ProcessedImage(image: image, dpiX: dpiX, dpiY: dpiY)
    }
}
