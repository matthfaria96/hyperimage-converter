public enum CropGeometry {
    /// The rectangle to keep, clamped to the image. Centred unless an origin is given.
    public static func rect(source: PixelSize, options: CropOptions, sourceDPI: Double) -> PixelRect {
        let requested: (w: Double, h: Double) = switch options.mode {
        case .pixels: (Double(options.width), Double(options.height))
        case .printSize: (options.printUnit.pixels(options.printWidth, dpi: sourceDPI), options.printUnit.pixels(options.printHeight, dpi: sourceDPI))
        case .aspectRatio: (options.ratioWidth, options.ratioHeight)
        }
        var w = requested.w, h = requested.h
        if options.switchToMatchLongSides {
            let swap = (source.isPortrait && w > h) || (!source.isPortrait && source.width != source.height && h > w)
            if swap { (w, h) = (h, w) }
        }

        let sw = Double(source.width), sh = Double(source.height)
        if options.mode == .aspectRatio {
            let scale = min(sw / w, sh / h)
            w *= scale
            h *= scale
        }
        let width = min(source.width, roundedPixels(w))
        let height = min(source.height, roundedPixels(h))

        let usesOrigin = options.useOrigin && options.mode == .pixels
        let x = usesOrigin ? options.originX : (source.width - width) / 2
        let y = usesOrigin ? options.originY : (source.height - height) / 2
        return PixelRect(
            x: min(max(0, x), source.width - width),
            y: min(max(0, y), source.height - height),
            width: width,
            height: height)
    }
}
