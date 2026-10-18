public enum ResizeMode: String, Codable, CaseIterable, Sendable {
    case pixels, percentage, printSize, oneSide
}

public enum ResizeSide: String, Codable, CaseIterable, Sendable {
    case width, height, longSide, shortSide
}

public enum ResizeFilter: String, Codable, CaseIterable, Sendable {
    case none, bell, bicubic, bilinear, bspline, fastLinear, lanczos2, lanczos3, linear, mitchell, nearest, triangle
}

public struct ResizeOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var mode = ResizeMode.pixels
    public var width = 800
    public var height = 600
    public var percentage = 50.0
    public var printWidth = 6.0
    public var printHeight = 4.0
    public var printUnit = LengthUnit.inch
    public var printDPI = 300.0
    public var side = ResizeSide.width
    public var sideLength = 800
    public var filter = ResizeFilter.lanczos3
    public var switchToMatchLongSides = false
    public var preserveAspectRatio = true
    public var smartCropping = false
    public var smartFilling = false
    public var fillColor = RGBAColor.white
    public var onlyIfLarger = false

    public init() {}
}
