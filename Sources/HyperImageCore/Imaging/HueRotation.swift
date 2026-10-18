import CoreImage
import CoreImage.CIFilterBuiltins

/// Hue shift in HSV space through a colour cube (Core Image's CIHueAdjust rotates in a different space).
enum HueRotation {
    static let size = 33

    static func apply(_ image: CIImage, degrees: Double) -> CIImage {
        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = image
        cube.cubeDimension = Float(size)
        cube.cubeData = table(degrees: degrees)
        cube.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        return cube.outputImage ?? image
    }

    static func table(degrees: Double) -> Data {
        var values = [Float]()
        values.reserveCapacity(size * size * size * 4)
        let n = Double(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rgb = rotate(Double(r) / n, Double(g) / n, Double(b) / n, by: degrees)
                    values += [Float(rgb.0), Float(rgb.1), Float(rgb.2), 1]
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func rotate(_ r: Double, _ g: Double, _ b: Double, by degrees: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        guard delta > 0 else { return (r, g, b) }
        var h: Double
        if maxC == r { h = (g - b) / delta } else if maxC == g { h = (b - r) / delta + 2 } else { h = (r - g) / delta + 4 }
        h = (h * 60 + degrees).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let s = delta / maxC, v = maxC
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r1, g1, b1): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
}
