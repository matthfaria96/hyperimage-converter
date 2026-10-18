/// Number of colours for the Color Depth step (24 = true colour).
public enum ColorDepth: Int, Codable, CaseIterable, Sendable {
    case trueColor = 24, bits8 = 8, bits7 = 7, bits6 = 6, bits5 = 5, bits4 = 4, bits3 = 3, bits2 = 2, bits1 = 1

    public var colorCount: Int? { self == .trueColor ? nil : 1 << rawValue }
}

public struct ColorDepthOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var depth = ColorDepth.trueColor

    public init() {}
}

public struct AdjustmentOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var brightness = 0.0      // -255...255
    public var contrast = 0.0        // -100...100
    public var gamma = 1.0           // 0...10
    public var hue = 0.0             // -180...180
    public var saturation = 0.0      // -100...100
    public var lightness = 0.0       // -100...100
    public var red = 0.0             // -255...255
    public var green = 0.0
    public var blue = 0.0
    public var shadows = 0.0         // -100...100
    public var highlights = 0.0      // -100...100
    public var sharpen = 0.0         // -100...100, negative softens
    public var unsharpMask = false
    public var unsharpRadius = 1.0
    public var grayscale = false
    public var negative = false
    public var sepia = false
    public var beforeResize = false

    public init() {}

    /// True when applying the adjustments would change any pixel.
    public var isIdentity: Bool {
        brightness == 0 && contrast == 0 && gamma == 1 && hue == 0 && saturation == 0 && lightness == 0
            && red == 0 && green == 0 && blue == 0 && shadows == 0 && highlights == 0 && sharpen == 0
            && !unsharpMask && !grayscale && !negative && !sepia
    }

    /// Same values with every slider and toggle back at its neutral position (keeps `enabled`/`beforeResize`).
    public func neutralized() -> AdjustmentOptions {
        var copy = AdjustmentOptions()
        copy.enabled = enabled
        copy.beforeResize = beforeResize
        return copy
    }
}

public struct DPIOptions: Codable, Equatable, Sendable {
    public var enabled = false
    public var x = 300.0
    public var y = 300.0

    public init() {}
}
