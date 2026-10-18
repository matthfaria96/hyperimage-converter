/// New canvas size and where the existing image's top-left corner lands on it (may be negative when shrinking).
public struct CanvasPlan: Equatable, Sendable {
    public var size: PixelSize
    public var imageOrigin: (x: Int, y: Int)

    public static func == (lhs: CanvasPlan, rhs: CanvasPlan) -> Bool {
        lhs.size == rhs.size && lhs.imageOrigin == rhs.imageOrigin
    }
}

public enum CanvasGeometry {
    public static func plan(source: PixelSize, options: CanvasOptions) -> CanvasPlan {
        switch options.mode {
        case .pixels:
            var size = PixelSize(width: max(1, options.width), height: max(1, options.height))
            if options.switchForPortrait && source.isPortrait { size = size.swapped() }
            return aligned(source: source, size: size, options: options)
        case .percentage:
            var (pw, ph) = (options.percentWidth, options.percentHeight)
            if options.switchForPortrait && source.isPortrait { (pw, ph) = (ph, pw) }
            let size = PixelSize(width: roundedPixels(Double(source.width) * pw / 100), height: roundedPixels(Double(source.height) * ph / 100))
            return aligned(source: source, size: size, options: options)
        case .expand:
            return expanded(source: source, options: options)
        }
    }

    private static func aligned(source: PixelSize, size: PixelSize, options: CanvasOptions) -> CanvasPlan {
        let dx = size.width - source.width
        let dy = size.height - source.height
        let x = switch options.horizontalAlignment {
        case .left: 0
        case .center: dx / 2
        case .right: dx
        }
        let y = switch options.verticalAlignment {
        case .top: 0
        case .center: dy / 2
        case .bottom: dy
        }
        return CanvasPlan(size: size, imageOrigin: (x, y))
    }

    private static func expanded(source: PixelSize, options: CanvasOptions) -> CanvasPlan {
        var (h, v) = (options.expandHorizontal, options.expandVertical)
        if options.switchForPortrait && source.isPortrait { (h, v) = (v, h) }
        // The amount is added on each chosen side ("Both" adds it twice), as in the reference output.
        let perX: Int, perY: Int
        switch options.expandUnit {
        case .pixels:
            perX = max(0, Int(h.rounded()))
            perY = max(0, Int(v.rounded()))
        case .percentage:
            perX = max(0, Int((Double(source.width) * h / 100).rounded()))
            perY = max(0, Int((Double(source.height) * v / 100).rounded()))
        }
        let addX = options.horizontalSide == .both ? perX * 2 : perX
        let addY = options.verticalSide == .both ? perY * 2 : perY
        let x = options.horizontalSide == .right ? 0 : perX
        let y = options.verticalSide == .bottom ? 0 : perY
        return CanvasPlan(size: PixelSize(width: source.width + addX, height: source.height + addY), imageOrigin: (x, y))
    }
}
