public enum RotationAngle: Int, Codable, CaseIterable, Sendable {
    case counterClockwise90 = -90
    case clockwise90 = 90
    case halfTurn = 180
}

public struct RotateOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var flipHorizontal = false
    public var flipVertical = false
    public var rotate = false
    public var angle = RotationAngle.clockwise90

    public init() {}
}

public enum CropMode: String, Codable, CaseIterable, Sendable {
    case pixels, printSize, aspectRatio
}

public struct CropOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var mode = CropMode.pixels
    public var width = 640
    public var height = 480
    public var printWidth = 6.0
    public var printHeight = 4.0
    public var printUnit = LengthUnit.inch
    public var ratioWidth = 4.0
    public var ratioHeight = 3.0
    public var switchToMatchLongSides = true
    public var losslessJPEG = true
    public var useOrigin = false
    public var originX = 0
    public var originY = 0

    public init() {}
}

public enum CanvasMode: String, Codable, CaseIterable, Sendable {
    case pixels, percentage, expand
}

public enum CanvasExpandUnit: String, Codable, CaseIterable, Sendable {
    case pixels, percentage
}

public enum HorizontalExpandSide: String, Codable, CaseIterable, Sendable {
    case left, right, both
}

public enum VerticalExpandSide: String, Codable, CaseIterable, Sendable {
    case top, bottom, both
}

public struct CanvasOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var mode = CanvasMode.pixels
    public var width = 800
    public var height = 600
    public var percentWidth = 110.0
    public var percentHeight = 110.0
    public var expandHorizontal = 10.0
    public var expandVertical = 10.0
    public var horizontalSide = HorizontalExpandSide.both
    public var verticalSide = VerticalExpandSide.both
    public var expandUnit = CanvasExpandUnit.percentage
    public var background = RGBAColor.white
    public var switchForPortrait = false
    public var horizontalAlignment = HorizontalAlignment.center
    public var verticalAlignment = VerticalAlignment.center

    public init() {}
}
