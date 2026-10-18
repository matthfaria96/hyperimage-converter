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
        if watermark.enabled, watermark.imagePath.isEmpty {
            return String(localized: "Escolha a imagem da marca d'água.")
        }
        return nil
    }

    public static func load(from url: URL) throws -> AdvancedOptions {
        try JSONDecoder().decode(AdvancedOptions.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
