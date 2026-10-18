import CoreGraphics

/// Frames (innermost first), an optional inner frame painted over the photo, and a drop shadow.
/// Frames and the shadow grow the image, as in the reference output (1200×800 → 1241×841 by default).
public enum BorderEffect {
    public struct Layout: Equatable, Sendable {
        public var canvas: PixelSize
        public var framedRect: CGRect      // photo + frames, top-left origin
        public var photoRect: CGRect
    }

    public static func layout(for size: PixelSize, options: BorderOptions) -> Layout {
        let frames = [options.frame1, options.frame2, options.frame3].filter(\.enabled).map(\.width).reduce(0, +)
        let framed = CGSize(width: size.width + 2 * frames, height: size.height + 2 * frames)
        var lead = 0, trail = 0
        if options.shadow.enabled {
            lead = 3 * options.shadow.radius + 1
            trail = 3 * options.shadow.radius + options.shadow.depth - 1
        }
        let canvas = PixelSize(width: Int(framed.width) + lead + trail, height: Int(framed.height) + lead + trail)
        let framedRect = CGRect(x: lead, y: lead, width: Int(framed.width), height: Int(framed.height))
        return Layout(canvas: canvas, framedRect: framedRect, photoRect: framedRect.insetBy(dx: CGFloat(frames), dy: CGFloat(frames)))
    }

    public static func apply(_ options: BorderOptions, to image: CGImage) throws -> CGImage {
        let l = layout(for: image.pixelSize, options: options)
        return try renderImage(width: l.canvas.width, height: l.canvas.height, colorSpace: image.workingColorSpace) { ctx in
            let all = CGRect(x: 0, y: 0, width: l.canvas.width, height: l.canvas.height)
            if options.shadow.enabled {
                ctx.setFillColor(options.shadow.background.cgColor)
                ctx.fill(all)
                ctx.saveGState()
                let depth = CGFloat(options.shadow.depth)
                // Flipped context: positive y offset moves the shadow down.
                ctx.setShadow(offset: CGSize(width: depth, height: depth), blur: CGFloat(options.shadow.radius) * 2.5,
                              color: options.shadow.color.cgColor)
                ctx.setFillColor(options.shadow.background.cgColor)
                ctx.fill(l.framedRect)
                ctx.restoreGState()
            }
            drawFrames(options, in: ctx, outer: l.framedRect)
            ctx.drawUpright(image, in: l.photoRect)
            if options.innerFrame.enabled { drawInnerFrame(options.innerFrame, in: ctx, photo: l.photoRect) }
        }
    }

    private static func drawFrames(_ options: BorderOptions, in ctx: CGContext, outer: CGRect) {
        // Paint from the outermost frame inwards, each one a filled rect over the previous.
        var rect = outer
        for frame in [options.frame3, options.frame2, options.frame1] where frame.enabled {
            ctx.setFillColor(frame.color.cgColor)
            ctx.fill(rect)
            rect = rect.insetBy(dx: CGFloat(frame.width), dy: CGFloat(frame.width))
        }
    }

    private static func drawInnerFrame(_ inner: InnerFrame, in ctx: CGContext, photo: CGRect) {
        let distance = CGFloat(inner.distance)
        let line = photo.insetBy(dx: distance, dy: distance)
        guard line.width > 0, line.height > 0 else { return }
        ctx.saveGState()
        ctx.addRect(photo)
        ctx.addRect(line)
        ctx.setFillColor(inner.fillColor.cgColor.copy(alpha: inner.fillOpacity / 100) ?? inner.fillColor.cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(inner.color.cgColor)
        ctx.setLineWidth(CGFloat(inner.width))
        let w = CGFloat(inner.width) / 2
        ctx.stroke(line.insetBy(dx: -w, dy: -w))
        ctx.restoreGState()
    }
}
