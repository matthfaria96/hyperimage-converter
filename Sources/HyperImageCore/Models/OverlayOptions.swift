public struct TextOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var text = "$H1"
    public var alignment = HorizontalAlignment.left
    public var position = OverlayPosition.bottomRight
    public var offsetX = 10
    public var offsetY = 10
    public var shadow = true
    public var color = RGBAColor.white
    public var background = false
    public var backgroundColor = RGBAColor.red
    public var roundedBackground = false
    public var fontFamily = "Verdana"
    public var bold = true
    public var italic = false
    public var fontSize = 28.0
    public var opacity = 100.0

    public init() {}
}

public struct WatermarkOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var imagePath = ""
    public var position = OverlayPosition.bottomRight
    public var offsetX = 10
    public var offsetY = 10
    public var shadow = false
    public var roundedCorners = false
    public var opacity = 100.0
    /// Watermark width as a percentage of the image width; 0 keeps the watermark's own size.
    public var relativeWidth = 0.0

    public init() {}
}

public struct FrameLine: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var width: Int
    public var color: RGBAColor
}

public struct InnerFrame: Codable, Equatable, Sendable {
    public var enabled = false
    public var distance = 20
    public var width = 1
    public var color = RGBAColor.white
    public var fillColor = RGBAColor.black
    public var fillOpacity = 30.0
}

public struct BorderShadow: Codable, Equatable, Sendable {
    public var enabled = true
    public var radius = 3
    public var depth = 3
    public var background = RGBAColor.white
    public var color = RGBAColor.black
}

public struct BorderOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var frame1 = FrameLine(enabled: true, width: 10, color: .white)
    public var frame2 = FrameLine(enabled: false, width: 1, color: .black)
    public var frame3 = FrameLine(enabled: false, width: 2, color: .white)
    public var innerFrame = InnerFrame()
    public var shadow = BorderShadow()

    public init() {}
}
