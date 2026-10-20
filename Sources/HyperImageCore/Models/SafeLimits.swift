import Foundation

/// Upper bounds for image dimensions coming from options files or the UI.
public enum SafeLimits {
    /// Largest accepted size for any one side, in pixels.
    public static let maxSide = 30_000
    /// Largest accepted image area, in pixels (400 MP).
    public static let maxPixels = 400_000_000
    /// 2^53: beyond this a Double no longer holds every integer exactly.
    static let maxExactDouble = 9_007_199_254_740_992.0
}

extension Int {
    /// Rounds `value` to an Int, or nil when it is NaN, infinite or too large to convert safely.
    init?(safe value: Double) {
        guard value.isFinite, abs(value) < SafeLimits.maxExactDouble else { return nil }
        self.init(value.rounded())
    }
}
