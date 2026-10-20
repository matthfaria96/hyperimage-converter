import Foundation

/// Every "Advanced Options" step. Saved to `.hyperoptions` files as JSON.
public struct AdvancedOptions: Codable, Equatable, Sendable {
    public var resize = ResizeOptions()
    public var rotate = RotateOptions()
    public var crop = CropOptions()
    public var canvas = CanvasOptions()
    public var colorDepth = ColorDepthOptions()
    public var adjustments = AdjustmentOptions()
    public var dpi = DPIOptions()
    public var text = TextOptions()
    public var watermark = WatermarkOptions()
    public var border = BorderOptions()

    public init() {}

    public var hasEnabledStep: Bool {
        resize.enabled || rotate.enabled || crop.enabled || canvas.enabled || colorDepth.enabled
            || adjustments.enabled || dpi.enabled || text.enabled || watermark.enabled || border.enabled
    }

    /// Validates values the pipeline cannot work with; returns a user-facing message or nil.
    public func validationError() -> String? {
        if resize.enabled {
            switch resize.mode {
            case .pixels where resize.width <= 0 || resize.height <= 0,
                 .percentage where resize.percentage <= 0,
                 .printSize where resize.printWidth <= 0 || resize.printHeight <= 0 || resize.printDPI <= 0,
                 .oneSide where resize.sideLength <= 0:
                return String(localized: "O novo tamanho na aba Redimensionar deve ser maior que 0.")
            default: break
            }
        }
        if crop.enabled {
            let invalid = switch crop.mode {
            case .pixels: crop.width <= 0 || crop.height <= 0
            case .printSize: crop.printWidth <= 0 || crop.printHeight <= 0
            case .aspectRatio: crop.ratioWidth <= 0 || crop.ratioHeight <= 0
            }
            if invalid { return String(localized: "O tamanho do recorte deve ser maior que 0.") }
        }
        if canvas.enabled, canvas.mode == .pixels, canvas.width <= 0 || canvas.height <= 0 {
            return String(localized: "O tamanho da tela deve ser maior que 0.")
        }
        if dpi.enabled, dpi.x <= 0 || dpi.y <= 0 {
            return String(localized: "O DPI deve ser maior que 0.")
        }
        if let limit = limitError() { return limit }
        if watermark.enabled, watermark.imagePath.isEmpty {
            return String(localized: "Escolha a imagem da marca d'água.")
        }
        return nil
    }

    /// Rejects pixel sizes above `SafeLimits` so hostile or mistyped values never reach allocation.
    private func limitError() -> String? {
        if resize.enabled {
            let tooBig = switch resize.mode {
            case .pixels: Self.exceeds(resize.width, resize.height)
            case .oneSide: resize.sideLength > SafeLimits.maxSide
            default: false
            }
            if tooBig { return String(localized: "O tamanho na aba Redimensionar passa do limite de 30 000 px por lado ou 400 megapixels.") }
        }
        if crop.enabled, crop.mode == .pixels, Self.exceeds(crop.width, crop.height) {
            return String(localized: "O tamanho do recorte passa do limite de 30 000 px por lado ou 400 megapixels.")
        }
        if canvas.enabled, canvas.mode == .pixels, Self.exceeds(canvas.width, canvas.height) {
            return String(localized: "O tamanho da tela passa do limite de 30 000 px por lado ou 400 megapixels.")
        }
        if border.enabled {
            let sizes = [border.frame1.width, border.frame2.width, border.frame3.width,
                         border.innerFrame.distance, border.innerFrame.width, border.shadow.radius, border.shadow.depth]
            if sizes.contains(where: { $0 > SafeLimits.maxSide || $0 < -SafeLimits.maxSide }) {
                return String(localized: "A espessura da borda passa do limite de 30 000 px.")
            }
        }
        return nil
    }

    private static func exceeds(_ width: Int, _ height: Int) -> Bool {
        guard width <= SafeLimits.maxSide, height <= SafeLimits.maxSide else { return true }
        let (area, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow || area > SafeLimits.maxPixels
    }

    public static func load(from url: URL) throws -> AdvancedOptions {
        try TolerantJSON.decode(AdvancedOptions.self, from: Data(contentsOf: url), defaults: AdvancedOptions())
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
