import CoreGraphics

/// Where the resampled image goes: a canvas of `canvas` size, the image drawn into `imageRect`
/// (which may overflow the canvas for smart cropping or leave margins for smart filling).
public struct ResizePlan: Equatable, Sendable {
    public var canvas: PixelSize
    public var imageRect: CGRect

    public var needsFill: Bool {
        imageRect.minX > 0.5 || imageRect.minY > 0.5
            || imageRect.maxX < Double(canvas.width) - 0.5 || imageRect.maxY < Double(canvas.height) - 0.5
    }
}

public enum ResizeGeometry {
    /// Returns nil when the image should be left at its current size.
    public static func plan(source: PixelSize, options: ResizeOptions, sourceDPI: Double) -> ResizePlan? {
        let sw = Double(source.width), sh = Double(source.height)
        switch options.mode {
        case .percentage:
            let scale = options.percentage / 100
            return uniform(source: source, scale: scale, onlyIfLarger: options.onlyIfLarger)
        case .oneSide:
            let length = Double(options.sideLength)
            let reference = switch options.side {
            case .width: sw
            case .height: sh
            case .longSide: max(sw, sh)
            case .shortSide: min(sw, sh)
            }
            return uniform(source: source, scale: length / reference, onlyIfLarger: options.onlyIfLarger)
        case .pixels:
            return box(source: source, target: PixelSize(width: options.width, height: options.height), options: options)
        case .printSize:
            let dpi = options.printDPI
            let target = PixelSize(
                width: roundedPixels(options.printUnit.pixels(options.printWidth, dpi: dpi)),
                height: roundedPixels(options.printUnit.pixels(options.printHeight, dpi: dpi)))
            return box(source: source, target: target, options: options)
        }
    }

    private static func uniform(source: PixelSize, scale: Double, onlyIfLarger: Bool) -> ResizePlan? {
        if onlyIfLarger && scale >= 1 { return nil }
        let size = PixelSize(width: roundedPixels(Double(source.width) * scale), height: roundedPixels(Double(source.height) * scale))
        return ResizePlan(canvas: size, imageRect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }

    private static func box(source: PixelSize, target requested: PixelSize, options: ResizeOptions) -> ResizePlan? {
        let target = options.switchToMatchLongSides ? requested.matchingOrientation(of: source) : requested
        let sw = Double(source.width), sh = Double(source.height)
        let tw = Double(target.width), th = Double(target.height)

        guard options.preserveAspectRatio else {
            if options.onlyIfLarger && source.width <= target.width && source.height <= target.height { return nil }
            return ResizePlan(canvas: target, imageRect: CGRect(x: 0, y: 0, width: tw, height: th))
        }

        let fitScale = min(tw / sw, th / sh)
        let fillScale = max(tw / sw, th / sh)
        if options.smartCropping || options.smartFilling {
            let scale = options.smartCropping ? fillScale : fitScale
            if options.onlyIfLarger && scale >= 1 { return nil }
            let w = sw * scale, h = sh * scale
            let rect = CGRect(x: ((tw - w) / 2).rounded(), y: ((th - h) / 2).rounded(), width: w.rounded(), height: h.rounded())
            return ResizePlan(canvas: target, imageRect: rect)
        }
        if options.onlyIfLarger && fitScale >= 1 { return nil }
        return uniform(source: source, scale: fitScale, onlyIfLarger: false)
    }
}
