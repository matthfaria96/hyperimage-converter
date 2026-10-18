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
        if o.contrast != 0 || o.saturation != 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = Float(1 + o.contrast / 100)
            controls.saturation = Float(1 + o.saturation / 100)
            controls.brightness = 0
            image = controls.outputImage ?? image
        }
        if o.gamma != 1 {
            let gamma = CIFilter.gammaAdjust()
            gamma.inputImage = image
            gamma.power = Float(1 / max(0.01, o.gamma))
            image = gamma.outputImage ?? image
        }
        if o.hue != 0 {
            let hue = CIFilter.hueAdjust()
            hue.inputImage = image
            hue.angle = Float(o.hue * .pi / 180)
            image = hue.outputImage ?? image
        }
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
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = image
            sharpen.sharpness = Float(o.sharpen / 100 * 2)
            sharpen.radius = 1.5
            image = sharpen.outputImage ?? image
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
        if o.grayscale {
            let mono = CIFilter.colorControls()
            mono.inputImage = image
            mono.saturation = 0
            image = mono.outputImage ?? image
        }
        if o.sepia {
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = image
            sepia.intensity = 1
            image = sepia.outputImage ?? image
        }
        if o.negative {
            let invert = CIFilter.colorInvert()
            invert.inputImage = image
            image = invert.outputImage ?? image
        }
        return image
    }

    /// Positive values blend towards white, negative towards black.
    private static func lightness(_ image: CIImage, amount: Double) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let k = CGFloat(min(1, max(-1, amount)))
        let scale = k > 0 ? 1 - k : 1 + k
        let bias = k > 0 ? k : 0
        matrix.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        matrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        return matrix.outputImage ?? image
    }
}
