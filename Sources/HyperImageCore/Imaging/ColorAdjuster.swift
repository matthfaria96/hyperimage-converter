import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies the Adjustments tab with Core Image.
public enum ColorAdjuster {
    // Work on gamma-encoded sRGB values so offsets behave like the original's per-pixel maths (negative = 255 - v).
    static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])

    public static func apply(_ options: AdjustmentOptions, to image: CGImage) throws -> CGImage {
        if options.isIdentity { return image }
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let output = filtered(input, options).cropped(to: extent)
        let space = image.workingColorSpace
        guard let result = context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: space) else {
            throw ImagingError.cannotAllocate(width: image.width, height: image.height)
        }
        return result
    }

    static func filtered(_ input: CIImage, _ o: AdjustmentOptions) -> CIImage {
        var image = input.clampedToExtent()

        if o.brightness != 0 || o.red != 0 || o.green != 0 || o.blue != 0 {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            let base = o.brightness / 255
            matrix.biasVector = CIVector(x: base + o.red / 255, y: base + o.green / 255, z: base + o.blue / 255, w: 0)
            image = matrix.outputImage ?? image
        }
        if o.contrast != 0 { image = contrast(image, amount: o.contrast / 100, extent: input.extent) }
        if o.saturation != 0 { image = saturate(image, factor: 1 + o.saturation / 100) }
        if o.gamma != 1 {
            let gamma = CIFilter.gammaAdjust()
            gamma.inputImage = image
            gamma.power = Float(1 / max(0.01, o.gamma))
            image = gamma.outputImage ?? image
        }
        if o.hue != 0 { image = HueRotation.apply(image, degrees: o.hue) }
        if o.lightness != 0 {
            image = lightness(image, amount: o.lightness / 100)
        }
        if o.shadows != 0 || o.highlights != 0 {
            let curve = CIFilter.toneCurve()
            curve.inputImage = image
            curve.point0 = CGPoint(x: 0, y: 0)
            curve.point1 = CGPoint(x: 0.25, y: 0.25 + 0.15 * o.shadows / 100)
            curve.point2 = CGPoint(x: 0.5, y: 0.5)
            curve.point3 = CGPoint(x: 0.75, y: 0.75 + 0.15 * o.highlights / 100)
            curve.point4 = CGPoint(x: 1, y: 1)
            image = curve.outputImage ?? image
        }
        if o.sharpen > 0 {
            // Unsharp mask fitted to the original's halo (radius 2.5, intensity 2.0 at 100).
            let usm = CIFilter.unsharpMask()
            usm.inputImage = image
            usm.radius = 2.5
            usm.intensity = Float(o.sharpen / 100 * 2.0)
            image = usm.outputImage ?? image
        } else if o.sharpen < 0 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image
            blur.radius = Float(-o.sharpen / 100 * 3)
            image = blur.outputImage ?? image
        }
        if o.unsharpMask {
            let usm = CIFilter.unsharpMask()
            usm.inputImage = image
            usm.radius = Float(o.unsharpRadius)
            usm.intensity = 0.8
            image = usm.outputImage ?? image
        }
        if o.grayscale || o.sepia { image = saturate(image, factor: 0) }
        if o.sepia {
            // Least-squares fit of the original app's sepia against Rec.601 grey.
            let tint = CIFilter.colorMatrix()
            tint.inputImage = image
            tint.rVector = CIVector(x: 0.996, y: 0, z: 0, w: 0)
            tint.gVector = CIVector(x: 0, y: 0.879, z: 0, w: 0)
            tint.bVector = CIVector(x: 0, y: 0, z: 0.611, w: 0)
            tint.biasVector = CIVector(x: 8.2 / 255, y: 7.2 / 255, z: 6.7 / 255, w: 0)
            image = tint.outputImage ?? image
        }
        if o.negative {
            let invert = CIFilter.colorInvert()
            invert.inputImage = image
            image = invert.outputImage ?? image
        }
        return image
    }

    /// Adds (or subtracts) light: as in the original, +50 already turns everything white.
    private static func lightness(_ image: CIImage, amount: Double) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let k = CGFloat(min(1, max(-1, amount))) * 2
        let scale: CGFloat = k < 0 ? max(0, 1 + k) : 1
        let bias: CGFloat = k > 0 ? k : 0
        matrix.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        matrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        return matrix.outputImage ?? image
    }

    /// Lerp between Rec.601 grey and the colour (the weights fitted from the reference output).
    private static func saturate(_ image: CIImage, factor: Double) -> CIImage {
        let s = CGFloat(factor), w: [CGFloat] = [0.299, 0.587, 0.114]
        func row(_ i: Int) -> CIVector {
            let v = (0..<3).map { j in w[j] * (1 - s) + (i == j ? s : 0) }
            return CIVector(x: v[0], y: v[1], z: v[2], w: 0)
        }
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = row(0)
        matrix.gVector = row(1)
        matrix.bVector = row(2)
        return matrix.outputImage ?? image
    }

    /// Stretches each channel around that channel's image mean (the original's pivot), ×1.78 at +50.
    private static func contrast(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage {
        let k = CGFloat(amount >= 0 ? 1 + 1.56 * amount : 1 + amount)
        let mean = channelMeans(image.cropped(to: extent))
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: k, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: k, w: 0)
        matrix.biasVector = CIVector(x: mean[0] * (1 - k), y: mean[1] * (1 - k), z: mean[2] * (1 - k), w: 0)
        return matrix.outputImage ?? image
    }

    static func channelMeans(_ image: CIImage) -> [CGFloat] {
        let average = CIFilter.areaAverage()
        average.inputImage = image
        average.extent = image.extent
        var pixel = [Float](repeating: 0, count: 4)
        guard let output = average.outputImage else { return [0.5, 0.5, 0.5] }
        context.render(output, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return pixel.prefix(3).map { CGFloat($0) }
    }
}
