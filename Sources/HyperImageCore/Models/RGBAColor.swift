import CoreGraphics

/// Codable sRGB colour with components in 0...1.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let red = RGBAColor(red: 1, green: 0, blue: 0)

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public init(cgColor: CGColor) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil) ?? cgColor
        let c = converted.components ?? [0, 0, 0, 1]
        if c.count >= 4 {
            self.init(red: c[0], green: c[1], blue: c[2], alpha: c[3])
        } else {
            self.init(red: c[0], green: c[0], blue: c[0], alpha: c.count > 1 ? c[1] : 1)
        }
    }
}
