import CoreGraphics

public enum WatermarkOverlay {
    public static func apply(_ mark: CGImage, options: WatermarkOptions, to image: CGImage) throws -> CGImage {
        let width = image.width, height = image.height
        return try renderImage(width: width, height: height, colorSpace: image.workingColorSpace, flipped: false) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            draw(mark, options: options, in: ctx, canvas: CGSize(width: width, height: height))
        }
    }

    static func markSize(_ mark: CGImage, options: WatermarkOptions, canvas: CGSize) -> CGSize {
        guard options.relativeWidth > 0 else { return CGSize(width: mark.width, height: mark.height) }
        let w = canvas.width * options.relativeWidth / 100
        return CGSize(width: w.rounded(), height: (w * CGFloat(mark.height) / CGFloat(mark.width)).rounded())
    }

    static func draw(_ mark: CGImage, options: WatermarkOptions, in ctx: CGContext, canvas: CGSize) {
        let size = markSize(mark, options: options, canvas: canvas)
        let topLeft = overlayOrigin(size: size, in: canvas, position: options.position,
                                    offsetX: Double(options.offsetX), offsetY: Double(options.offsetY))
        let rect = CGRect(x: topLeft.x, y: canvas.height - topLeft.y - size.height, width: size.width, height: size.height)
        ctx.saveGState()
        ctx.setAlpha(options.opacity / 100)
        if options.shadow {
            ctx.setShadow(offset: CGSize(width: 3, height: -3), blur: 6, color: CGColor(gray: 0, alpha: 0.6))
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if options.roundedCorners {
            let radius = min(size.width, size.height) * 0.12
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
        }
        ctx.interpolationQuality = .high
        ctx.draw(mark, in: rect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
