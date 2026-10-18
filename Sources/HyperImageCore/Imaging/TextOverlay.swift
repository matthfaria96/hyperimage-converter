import CoreGraphics
import CoreText
import Foundation

/// Draws the "Add Text" overlay. Font size is in pixels and does not scale with the image.
public enum TextOverlay {
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
        let padding = options.background ? (options.fontSize * 0.25).rounded() : 0
        let box = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let topLeft = overlayOrigin(size: box, in: canvas, position: options.position,
                                    offsetX: Double(options.offsetX), offsetY: Double(options.offsetY))
        let boxRect = CGRect(x: topLeft.x, y: canvas.height - topLeft.y - box.height, width: box.width, height: box.height)

        ctx.saveGState()
        ctx.setAlpha(options.opacity / 100)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if options.background {
            let radius = options.roundedBackground ? min(box.height / 2, options.fontSize * 0.4) : 0
            ctx.addPath(CGPath(roundedRect: boxRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(options.backgroundColor.cgColor)
            ctx.fillPath()
        }
        if options.shadow {
            let offset = max(1, options.fontSize / 14)
            ctx.setShadow(offset: CGSize(width: offset, height: -offset), blur: offset * 1.5,
                          color: CGColor(gray: 0, alpha: 0.75))
        }
        let textRect = boxRect.insetBy(dx: padding, dy: padding)
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
        let base = CTFontCreateWithFontDescriptor(descriptor, options.fontSize, nil)
        let family = CTFontCopyFamilyName(base) as String
        if family.caseInsensitiveCompare(options.fontFamily) == .orderedSame { return base }
        let system = CTFontCreateUIFontForLanguage(.system, options.fontSize, nil) ?? base
        return CTFontCreateCopyWithSymbolicTraits(system, options.fontSize, nil, traits, traits) ?? system
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
