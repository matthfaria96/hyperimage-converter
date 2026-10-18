import CoreGraphics
import CoreText
import Foundation

/// Draws the "Add Text" overlay. The size does not scale with the image.
public enum TextOverlay {
    /// The font size is in Windows points, which the original renders at 96 dpi (28 pt → 37.3 px),
    /// matching its reference output.
    static func pixelSize(_ options: TextOptions) -> CGFloat { options.fontSize * 96 / 72 }

    public static func apply(_ text: String, options: TextOptions, to image: CGImage) throws -> CGImage {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return image }
        let width = image.width, height = image.height
        return try renderImage(width: width, height: height, colorSpace: image.workingColorSpace, flipped: false) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            draw(text, options: options, in: ctx, canvas: CGSize(width: width, height: height))
        }
    }

    /// Draws into an unflipped (bottom-left origin) context.
    static func draw(_ text: String, options: TextOptions, in ctx: CGContext, canvas: CGSize) {
        let attributed = attributedString(text, options: options)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude), nil)
        let textSize = CGSize(width: ceil(fit.width), height: ceil(fit.height))
        let px = pixelSize(options)
        // The text cell sits at the offset; the background hugs it (a hair wider), as in the reference output.
        let padding = options.background ? max(1, (px * 0.04).rounded()) : 0
        let box = CGSize(width: textSize.width + padding * 2, height: textSize.height)
        let topLeft = overlayOrigin(size: box, in: canvas, position: options.position,
                                    offsetX: Double(options.offsetX), offsetY: Double(options.offsetY))
        // GDI lays the glyphs about 0.11 em further right and down than Core Text; measured on the reference.
        let nudge = (px * 0.11).rounded()
        let boxRect = CGRect(x: topLeft.x + nudge, y: canvas.height - topLeft.y - box.height - nudge, width: box.width, height: box.height)

        ctx.saveGState()
        ctx.setAlpha(options.opacity / 100)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if options.background {
            let radius = options.roundedBackground ? min(box.height / 2, px * 0.4) : 0
            ctx.addPath(CGPath(roundedRect: boxRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(options.backgroundColor.cgColor)
            ctx.fillPath()
        }
        if options.shadow {
            let offset = max(1, px / 14)
            ctx.setShadow(offset: CGSize(width: offset, height: -offset), blur: offset * 1.5,
                          color: CGColor(gray: 0, alpha: 0.75))
        }
        let textRect = boxRect.insetBy(dx: padding, dy: 0)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Family + bold/italic traits; falls back to the system font when the family is missing.
    static func makeFont(_ options: TextOptions) -> CTFont {
        var traits: CTFontSymbolicTraits = []
        if options.bold { traits.insert(.traitBold) }
        if options.italic { traits.insert(.traitItalic) }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: options.fontFamily,
            kCTFontTraitsAttribute: [kCTFontSymbolicTrait: traits.rawValue],
        ] as CFDictionary)
        let base = CTFontCreateWithFontDescriptor(descriptor, pixelSize(options), nil)
        let family = CTFontCopyFamilyName(base) as String
        if family.caseInsensitiveCompare(options.fontFamily) == .orderedSame { return base }
        let system = CTFontCreateUIFontForLanguage(.system, pixelSize(options), nil) ?? base
        return CTFontCreateCopyWithSymbolicTraits(system, pixelSize(options), nil, traits, traits) ?? system
    }

    static func attributedString(_ text: String, options: TextOptions) -> CFAttributedString {
        let font = makeFont(options)
        var alignment: CTTextAlignment = switch options.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        let style = withUnsafeBytes(of: &alignment) { raw in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: options.color.cgColor,
            kCTParagraphStyleAttributeName: style,
        ]
        return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    }
}
