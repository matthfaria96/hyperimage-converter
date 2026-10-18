import CoreGraphics

/// Integer pixel rectangle (origin top-left, y grows downward).
public struct PixelRect: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var size: PixelSize { PixelSize(width: width, height: height) }
}

extension PixelSize {
    public var isPortrait: Bool { height > width }

    public func swapped() -> PixelSize { PixelSize(width: height, height: width) }

    /// Swaps the target so its long side lies on the same axis as `source`'s long side.
    func matchingOrientation(of source: PixelSize) -> PixelSize {
        let sourcePortrait = source.height > source.width
        let selfPortrait = height > width
        let differs = (sourcePortrait && width > height) || (!sourcePortrait && source.width != source.height && selfPortrait)
        return differs ? swapped() : self
    }
}

func roundedPixels(_ value: Double) -> Int { max(1, Int(value.rounded())) }

/// Places a `size` box inside a `container` at a 7-way anchor with an inset, top-left origin.
public func overlayOrigin(size: CGSize, in container: CGSize, position: OverlayPosition, offsetX: Double, offsetY: Double) -> CGPoint {
    let left = offsetX
    let right = container.width - size.width - offsetX
    let centerX = (container.width - size.width) / 2
    let top = offsetY
    let bottom = container.height - size.height - offsetY
    let centerY = (container.height - size.height) / 2
    return switch position {
    case .topLeft: CGPoint(x: left, y: top)
    case .topCenter: CGPoint(x: centerX, y: top)
    case .topRight: CGPoint(x: right, y: top)
    case .center: CGPoint(x: centerX, y: centerY)
    case .bottomLeft: CGPoint(x: left, y: bottom)
    case .bottomCenter: CGPoint(x: centerX, y: bottom)
    case .bottomRight: CGPoint(x: right, y: bottom)
    }
}
