import CoreGraphics

/// Creates an RGBA8 context of `size` whose user space has a top-left origin, runs `body`, returns the image.
func renderImage(width: Int, height: Int, colorSpace: CGColorSpace, flipped: Bool = true, _ body: (CGContext) throws -> Void) throws -> CGImage {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace, bitmapInfo: Bitmap.bitmapInfo) else {
        throw ImagingError.cannotAllocate(width: width, height: height)
    }
    ctx.interpolationQuality = .high
    if flipped {
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
    }
    try body(ctx)
    guard let image = ctx.makeImage() else { throw ImagingError.cannotAllocate(width: width, height: height) }
    return image
}

extension CGContext {
    /// Draws an image into a top-left-origin rect of a flipped context without turning it upside down.
    func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }
}

extension CGImage {
    var pixelSize: PixelSize { PixelSize(width: width, height: height) }

    /// RGB colour space used for processing this image (its own when RGB, otherwise sRGB).
    var workingColorSpace: CGColorSpace {
        if let space = colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }
}
