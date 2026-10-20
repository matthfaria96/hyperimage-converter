import Foundation

/// Imports FastStone Photo Resizer's `.ccf` option files (a Delphi `TOptionsInfo` stream) into `AdvancedOptions`.
/// Fields the file does not carry, or that hold values we do not recognise, keep their defaults.
public enum CCFImporter {
    public static func load(from url: URL) throws -> AdvancedOptions {
        try importOptions(Data(contentsOf: url))
    }

    public static func importOptions(_ data: Data) throws -> AdvancedOptions {
        let stream = try DelphiStream(data: data)
        guard stream.className == "TOptionsInfo" else { throw DelphiStreamError.notAComponentStream }
        let p = Fields(stream.properties)
        var o = AdvancedOptions()
        o.resize = resize(p, o.resize)
        o.rotate = rotate(p, o.rotate)
        o.crop = crop(p, o.crop)
        o.canvas = canvas(p, o.canvas)
        o.colorDepth.enabled = p.bool("UseColorDepth") ?? false
        if let index = p.int("colorDepthIndex"), ColorDepth.allCases.indices.contains(index) {
            o.colorDepth.depth = ColorDepth.allCases[index]
        }
        o.adjustments = adjustments(p, o.adjustments)
        o.dpi.enabled = p.bool("UseDPI") ?? false
        if let x = p.positive("DPIX") { o.dpi.x = x }
        if let y = p.positive("DPIY") { o.dpi.y = y }
        o.text = text(p, o.text)
        o.watermark = watermark(p, o.watermark)
        o.border = border(p, o.border)
        return o
    }

    private static func resize(_ p: Fields, _ base: ResizeOptions) -> ResizeOptions {
        var r = base
        r.enabled = p.bool("UseResize") ?? false
        r.mode = p.bool("BasedOneSide") == true ? .oneSide
            : p.bool("InPercentage") == true ? .percentage
            : p.bool("InPrintSize") == true ? .printSize : .pixels
        if let w = p.dimension("resizeWidth") { r.width = w }
        if let h = p.dimension("resizeHeight") { r.height = h }
        if let pct = p.positive("ResizePercentage") { r.percentage = pct }
        if let w = p.positive("ResizePW") { r.printWidth = w }
        if let h = p.positive("ResizePH") { r.printHeight = h }
        r.printUnit = p.int("ResizeUnit") == 1 ? .centimeter : .inch
        if let dpi = p.positive("ResizeDPI") { r.printDPI = dpi }
        if let side = p.int("BasedSideNo"), ResizeSide.allCases.indices.contains(side) { r.side = ResizeSide.allCases[side] }
        if let length = p.dimension("BasedSize") { r.sideLength = length }
        if let filter = p.int("ResizeFilter"), ResizeFilter.allCases.indices.contains(filter) { r.filter = ResizeFilter.allCases[filter] }
        r.switchToMatchLongSides = p.bool("SwitchWH") ?? r.switchToMatchLongSides
        r.preserveAspectRatio = p.bool("PreserveAspectRatio") ?? r.preserveAspectRatio
        r.smartCropping = p.bool("SmartCropping") ?? r.smartCropping
        r.smartFilling = p.bool("SmartExpanding") ?? r.smartFilling
        r.fillColor = p.color("SmartExpandColor") ?? r.fillColor
        r.onlyIfLarger = p.bool("ResizeOnlyLargerThan") ?? r.onlyIfLarger
        return r
    }

    private static func rotate(_ p: Fields, _ base: RotateOptions) -> RotateOptions {
        var r = base
        r.enabled = p.bool("UseRotate") ?? false
        r.flipHorizontal = p.bool("FlipHorizontal") ?? false
        r.flipVertical = p.bool("FlipVertical") ?? false
        r.rotate = p.bool("Rotate") ?? false
        if let angle = p.int("RotateIndex").flatMap(RotationAngle.init(rawValue:)) { r.angle = angle }
        return r
    }

    private static func crop(_ p: Fields, _ base: CropOptions) -> CropOptions {
        var c = base
        c.enabled = p.bool("UseCrop") ?? false
        if let method = p.int("CropMethod"), CropMode.allCases.indices.contains(method) { c.mode = CropMode.allCases[method] }
        c.useOrigin = p.bool("CropUseXY") ?? false
        c.originX = max(0, p.int("CropX") ?? 0)
        c.originY = max(0, p.int("CropY") ?? 0)
        if let w = p.dimension("CropW") { c.width = w }
        if let h = p.dimension("CropH") { c.height = h }
        if let w = p.positive("CropRW") { c.ratioWidth = w }
        if let h = p.positive("CropRH") { c.ratioHeight = h }
        if let w = p.positive("CropPW") { c.printWidth = w }
        if let h = p.positive("CropPH") { c.printHeight = h }
        c.printUnit = p.int("CropUnit") == 1 ? .centimeter : .inch
        c.switchToMatchLongSides = p.bool("CropSwitchWH") ?? c.switchToMatchLongSides
        c.losslessJPEG = p.bool("CropLossless") ?? c.losslessJPEG
        return c
    }

    private static func canvas(_ p: Fields, _ base: CanvasOptions) -> CanvasOptions {
        var c = base
        c.enabled = p.bool("UseCanvasResize") ?? false
        c.mode = p.bool("canvasExpand") == true ? .expand : (p.bool("canvasInPixel") ?? true) ? .pixels : .percentage
        if let w = p.dimension("canvasW") { c.width = w }
        if let h = p.dimension("canvasH") { c.height = h }
        if let w = p.positive("canvasW2") { c.percentWidth = w }
        if let h = p.positive("canvasH2") { c.percentHeight = h }
        if let w = p.positive("canvasW3") { c.expandHorizontal = w }
        if let h = p.positive("canvasH3") { c.expandVertical = h }
        c.expandUnit = (p.bool("canvasPercExpand") ?? true) ? .percentage : .pixels
        c.background = p.color("canvasBackgroundColor") ?? c.background
        c.switchForPortrait = p.bool("canvasBasePortrait") ?? c.switchForPortrait
        // Delphi TAlignment order: 0 left, 1 right, 2 centre. The same index picks the expand side (2 = both).
        switch p.int("canvasWAlign") {
        case 0: c.horizontalAlignment = .left; c.horizontalSide = .left
        case 1: c.horizontalAlignment = .right; c.horizontalSide = .right
        case 2: c.horizontalAlignment = .center; c.horizontalSide = .both
        default: break
        }
        switch p.int("canvasHAlign") {
        case 0: c.verticalAlignment = .top; c.verticalSide = .top
        case 1: c.verticalAlignment = .bottom; c.verticalSide = .bottom
        case 2: c.verticalAlignment = .center; c.verticalSide = .both
        default: break
        }
        return c
    }

    private static func adjustments(_ p: Fields, _ base: AdjustmentOptions) -> AdjustmentOptions {
        var a = base
        a.enabled = p.bool("UseEffects") ?? false
        a.brightness = p.double("brightness") ?? 0
        a.contrast = p.double("contrast") ?? 0
        a.gamma = p.double("gamma") ?? 1
        a.hue = p.double("hue") ?? 0
        a.saturation = p.double("saturation") ?? 0
        a.lightness = p.double("lightness") ?? 0
        a.red = p.double("red") ?? 0
        a.green = p.double("green") ?? 0
        a.blue = p.double("blue") ?? 0
        a.sharpen = p.double("Sharpen") ?? 0
        a.unsharpMask = p.bool("UseUSM") ?? false
        a.unsharpRadius = p.positive("USMRadius") ?? a.unsharpRadius
        a.shadows = p.double("shadows") ?? 0
        a.highlights = p.double("highlights") ?? 0
        a.grayscale = p.bool("grayScale") ?? false
        a.negative = p.bool("Negative") ?? false
        a.sepia = p.bool("Sepia") ?? false
        a.beforeResize = p.bool("AdjustBeforeResize") ?? false
        return a
    }

    private static func text(_ p: Fields, _ base: TextOptions) -> TextOptions {
        var t = base
        t.enabled = p.bool("UseText") ?? false
        // Delphi stores line breaks in TMemo text as CR LF.
        if let text = p.text("Text") { t.text = text.replacingOccurrences(of: "\r\n", with: "\n") }
        switch p.int("TextAlign") {
        case 0: t.alignment = .left
        case 1: t.alignment = .right
        case 2: t.alignment = .center
        default: break
        }
        if let position = p.position("TextPosition") { t.position = position }
        t.shadow = p.bool("TextShadow") ?? t.shadow
        t.color = p.color("TextColor") ?? t.color
        t.offsetX = p.int("TextX") ?? t.offsetX
        t.offsetY = p.int("TextY") ?? t.offsetY
        t.background = p.bool("TextBackground") ?? t.background
        t.backgroundColor = p.color("TextBackgroundColor") ?? t.backgroundColor
        t.roundedBackground = p.bool("TextRound") ?? t.roundedBackground
        if let font = p.text("TextFont"), !font.isEmpty { t.fontFamily = font }
        if let style = p.set("TextStyle") {
            t.bold = style.contains("fsBold")
            t.italic = style.contains("fsItalic")
        }
        if let size = p.positive("TextSize") { t.fontSize = size }
        if let opacity = p.double("TextTrans") { t.opacity = min(100, max(0, opacity)) }
        return t
    }

    private static func watermark(_ p: Fields, _ base: WatermarkOptions) -> WatermarkOptions {
        var w = base
        w.enabled = p.bool("UseWatermark") ?? false
        if let position = p.position("WaterPosition") { w.position = position }
        w.offsetX = p.int("WaterX") ?? w.offsetX
        w.offsetY = p.int("WaterY") ?? w.offsetY
        w.shadow = p.bool("WaterShadow") ?? w.shadow
        w.roundedCorners = p.bool("WaterRound") ?? w.roundedCorners
        if let opacity = p.double("WaterTrans") { w.opacity = min(100, max(0, opacity)) }
        return w
    }

    private static func border(_ p: Fields, _ base: BorderOptions) -> BorderOptions {
        var b = base
        b.enabled = p.bool("UseBorder") ?? false
        b.frame1 = frame(p, "1", b.frame1)
        b.frame2 = frame(p, "2", b.frame2)
        b.frame3 = frame(p, "3", b.frame3)
        b.innerFrame.enabled = p.bool("InFrame") ?? b.innerFrame.enabled
        b.innerFrame.distance = p.clampedInt("InFD") ?? b.innerFrame.distance
        b.innerFrame.width = p.clampedInt("InFW") ?? b.innerFrame.width
        b.innerFrame.color = p.color("InFC") ?? b.innerFrame.color
        b.innerFrame.fillColor = p.color("InFFC") ?? b.innerFrame.fillColor
        if let opacity = p.double("InFO") { b.innerFrame.fillOpacity = min(100, max(0, opacity)) }
        b.shadow.enabled = p.bool("BorderShadow") ?? b.shadow.enabled
        b.shadow.radius = p.clampedInt("RadiusEdit") ?? b.shadow.radius
        b.shadow.depth = p.clampedInt("DepthEdit") ?? b.shadow.depth
        b.shadow.background = p.color("ShadowBK") ?? b.shadow.background
        b.shadow.color = p.color("ShadowColor") ?? b.shadow.color
        return b
    }

    private static func frame(_ p: Fields, _ n: String, _ base: FrameLine) -> FrameLine {
        FrameLine(enabled: p.bool("Frame\(n)") ?? base.enabled,
                  width: p.clampedInt("F\(n)W") ?? base.width,
                  color: p.color("F\(n)C") ?? base.color)
    }

    /// Typed lookups over the stream's properties.
    struct Fields {
        let values: [String: DelphiValue]
        init(_ values: [String: DelphiValue]) { self.values = values }

        func bool(_ key: String) -> Bool? { values[key]?.bool }
        func int(_ key: String) -> Int? { values[key]?.int }
        func double(_ key: String) -> Double? { values[key]?.double }
        func text(_ key: String) -> String? { values[key]?.text }
        func positive(_ key: String) -> Double? { double(key).flatMap { $0 > 0 ? $0 : nil } }
        func positiveInt(_ key: String) -> Int? { int(key).flatMap { $0 > 0 ? $0 : nil } }
        /// A positive pixel dimension, capped at `SafeLimits.maxSide`.
        func dimension(_ key: String) -> Int? { positiveInt(key).map { min($0, SafeLimits.maxSide) } }
        /// A pixel size that may be zero or negative, kept within ±`SafeLimits.maxSide`.
        func clampedInt(_ key: String) -> Int? { int(key).map { Swift.min(Swift.max($0, -SafeLimits.maxSide), SafeLimits.maxSide) } }

        func set(_ key: String) -> [String]? {
            if case .set(let members)? = values[key] { members } else { nil }
        }

        /// The original lists positions in the same order as `OverlayPosition`.
        func position(_ key: String) -> OverlayPosition? {
            int(key).flatMap { OverlayPosition.allCases.indices.contains($0) ? OverlayPosition.allCases[$0] : nil }
        }

        func color(_ key: String) -> RGBAColor? {
            switch values[key] {
            case .identifier(let name)?: Self.namedColors[name].map(Self.color(bgr:))
            case .integer(let value)? where value >= 0: Self.color(bgr: value)
            default: nil
            }
        }

        /// TColor is 0x00BBGGRR.
        static func color(bgr: Int) -> RGBAColor {
            RGBAColor(red: Double(bgr & 0xFF) / 255, green: Double(bgr >> 8 & 0xFF) / 255, blue: Double(bgr >> 16 & 0xFF) / 255)
        }

        static let namedColors: [String: Int] = [
            "clBlack": 0x000000, "clMaroon": 0x000080, "clGreen": 0x008000, "clOlive": 0x008080,
            "clNavy": 0x800000, "clPurple": 0x800080, "clTeal": 0x808000, "clGray": 0x808080,
            "clSilver": 0xC0C0C0, "clRed": 0x0000FF, "clLime": 0x00FF00, "clYellow": 0x00FFFF,
            "clBlue": 0xFF0000, "clFuchsia": 0xFF00FF, "clAqua": 0xFFFF00, "clWhite": 0xFFFFFF,
            "clMoneyGreen": 0xC0DCC0, "clSkyBlue": 0xF0CAA6, "clCream": 0xF0FBFF, "clMedGray": 0xA4A0A0,
        ]
    }
}
