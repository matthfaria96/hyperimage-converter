import Foundation

/// Reconstruction kernels for the resampler: a support radius and a weight function.
struct ResampleKernel: Sendable {
    let support: Double
    let weight: @Sendable (Double) -> Double

    static func make(_ filter: ResizeFilter) -> ResampleKernel {
        switch filter {
        case .none, .nearest:
            ResampleKernel(support: 0.5) { abs($0) <= 0.5 ? 1 : 0 }
        case .fastLinear, .linear, .bilinear, .triangle:
            ResampleKernel(support: 1) { max(0, 1 - abs($0)) }
        case .bell:
            ResampleKernel(support: 1.5) { x in
                let t = abs(x)
                if t < 0.5 { return 0.75 - t * t }
                if t < 1.5 { return 0.5 * (t - 1.5) * (t - 1.5) }
                return 0
            }
        case .bspline:
            ResampleKernel(support: 2) { cubic($0, b: 1, c: 0) }
        case .bicubic:
            ResampleKernel(support: 2) { cubic($0, b: 0, c: 0.5) }
        case .mitchell:
            ResampleKernel(support: 2) { cubic($0, b: 1.0 / 3, c: 1.0 / 3) }
        case .lanczos2:
            ResampleKernel(support: 2) { lanczos($0, lobes: 2) }
        case .lanczos3:
            ResampleKernel(support: 3) { lanczos($0, lobes: 3) }
        }
    }

    /// Mitchell–Netravali family (B, C).
    private static func cubic(_ x: Double, b: Double, c: Double) -> Double {
        let t = abs(x)
        if t < 1 {
            return ((12 - 9 * b - 6 * c) * t * t * t + (-18 + 12 * b + 6 * c) * t * t + (6 - 2 * b)) / 6
        }
        if t < 2 {
            return ((-b - 6 * c) * t * t * t + (6 * b + 30 * c) * t * t + (-12 * b - 48 * c) * t + (8 * b + 24 * c)) / 6
        }
        return 0
    }

    private static func lanczos(_ x: Double, lobes: Double) -> Double {
        let t = abs(x)
        if t < 1e-8 { return 1 }
        if t >= lobes { return 0 }
        let px = Double.pi * t
        return lobes * sin(px) * sin(px / lobes) / (px * px)
    }
}

/// Precomputed taps for one output coordinate.
struct Contribution {
    let start: Int
    let weights: [Float]
}

func contributions(sourceLength: Int, targetLength: Int, kernel: ResampleKernel) -> [Contribution] {
    let scale = Double(targetLength) / Double(sourceLength)
    let stretch = max(1, 1 / scale)          // widen the kernel when shrinking (anti-aliasing)
    let radius = kernel.support * stretch
    return (0..<targetLength).map { i in
        let center = (Double(i) + 0.5) / scale
        let lo = max(0, Int((center - radius).rounded(.down)))
        let hi = min(sourceLength - 1, Int((center + radius).rounded(.up)))
        var weights = (lo...hi).map { j in kernel.weight((Double(j) + 0.5 - center) / stretch) }
        var total = weights.reduce(0, +)
        if total == 0 {
            let nearest = min(sourceLength - 1, max(0, Int(center)))
            return Contribution(start: nearest, weights: [1])
        }
        total = 1 / total
        weights = weights.map { $0 * total }
        return Contribution(start: lo, weights: weights.map(Float.init))
    }
}
