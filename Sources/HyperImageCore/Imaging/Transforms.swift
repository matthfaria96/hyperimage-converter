import CoreGraphics

/// Geometric steps that only move pixels around.
public enum Transforms {
    public static func resize(_ image: CGImage, plan: ResizePlan, filter: ResizeFilter, fill: RGBAColor) throws -> CGImage {
        let space = image.workingColorSpace
        let target = PixelSize(width: max(1, Int(plan.imageRect.width)), height: max(1, Int(plan.imageRect.height)))
        let source = try Bitmap(image: image, colorSpace: space)
        let scaled = try Resampler.resize(source, to: target, filter: filter).makeImage()
        let fillsCanvas = plan.imageRect == CGRect(x: 0, y: 0, width: plan.canvas.width, height: plan.canvas.height)
        if fillsCanvas { return scaled }
        return try renderImage(width: plan.canvas.width, height: plan.canvas.height, colorSpace: space) { ctx in
            ctx.setFillColor(fill.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: plan.canvas.width, height: plan.canvas.height))
            ctx.interpolationQuality = .none
            ctx.drawUpright(scaled, in: plan.imageRect)
        }
    }

    public static func flipRotate(_ image: CGImage, options: RotateOptions) throws -> CGImage {
        let quarter = options.rotate && options.angle != .halfTurn
        let w = quarter ? image.height : image.width
        let h = quarter ? image.width : image.height
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        return try renderImage(width: w, height: h, colorSpace: image.workingColorSpace, flipped: false) { ctx in
            ctx.interpolationQuality = .none
            // Work in the unflipped (bottom-left) space: rotate about the centre, then mirror.
            ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
            if options.rotate {
                // Clockwise on screen is a negative angle in Quartz' y-up space.
                ctx.rotate(by: -CGFloat(options.angle.rawValue) * .pi / 180)
            }
            ctx.scaleBy(x: options.flipHorizontal ? -1 : 1, y: options.flipVertical ? -1 : 1)
            ctx.draw(image, in: CGRect(x: -iw / 2, y: -ih / 2, width: iw, height: ih))
        }
    }

    public static func crop(_ image: CGImage, to rect: PixelRect) throws -> CGImage {
        let cg = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        guard let cropped = image.cropping(to: cg) else { throw ImagingError.cannotAllocate(width: rect.width, height: rect.height) }
        return cropped
    }

    public static func canvas(_ image: CGImage, plan: CanvasPlan, background: RGBAColor) throws -> CGImage {
        try renderImage(width: plan.size.width, height: plan.size.height, colorSpace: image.workingColorSpace) { ctx in
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: plan.size.width, height: plan.size.height))
            ctx.interpolationQuality = .none
            ctx.drawUpright(image, in: CGRect(x: plan.imageOrigin.x, y: plan.imageOrigin.y, width: image.width, height: image.height))
        }
    }

    public static func reduceColors(_ image: CGImage, count: Int) throws -> CGImage {
        let bitmap = try Bitmap(image: image, colorSpace: image.workingColorSpace)
        let indexed = Quantizer.quantize(bitmap, colors: count)
        return try Quantizer.expand(indexed, like: bitmap).makeImage()
    }
}
