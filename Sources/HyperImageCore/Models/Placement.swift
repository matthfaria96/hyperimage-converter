/// Anchor used by text and watermark overlays.
public enum OverlayPosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight, center, bottomLeft, bottomCenter, bottomRight
}

public enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case inch, centimeter

    /// Converts a length in this unit to pixels at the given resolution.
    public func pixels(_ value: Double, dpi: Double) -> Double {
        switch self {
        case .inch: value * dpi
        case .centimeter: value / 2.54 * dpi
        }
    }
}

public enum HorizontalAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

public enum VerticalAlignment: String, Codable, CaseIterable, Sendable {
    case top, center, bottom
}
