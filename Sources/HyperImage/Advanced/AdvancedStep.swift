import HyperImageCore

enum AdvancedStep: String, CaseIterable, Codable, Identifiable {
    case resize, rotate, crop, canvas, colorDepth, adjustments, dpi, text, watermark, border

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resize: String(localized: "Redimensionar")
        case .rotate: String(localized: "Girar / Espelhar")
        case .crop: String(localized: "Recortar")
        case .canvas: String(localized: "Tamanho da Tela")
        case .colorDepth: String(localized: "Profundidade de Cor")
        case .adjustments: String(localized: "Ajustes")
        case .dpi: String(localized: "DPI")
        case .text: String(localized: "Texto")
        case .watermark: String(localized: "Marca d'Água")
        case .border: String(localized: "Bordas")
        }
    }

    var symbol: String {
        switch self {
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .rotate: "rotate.right"
        case .crop: "crop"
        case .canvas: "rectangle.expand.vertical"
        case .colorDepth: "paintpalette"
        case .adjustments: "slider.horizontal.3"
        case .dpi: "printer"
        case .text: "textformat"
        case .watermark: "seal"
        case .border: "square.dashed"
        }
    }

    func isEnabled(in o: AdvancedOptions) -> Bool {
        switch self {
        case .resize: o.resize.enabled
        case .rotate: o.rotate.enabled
        case .crop: o.crop.enabled
        case .canvas: o.canvas.enabled
        case .colorDepth: o.colorDepth.enabled
        case .adjustments: o.adjustments.enabled
        case .dpi: o.dpi.enabled
        case .text: o.text.enabled
        case .watermark: o.watermark.enabled
        case .border: o.border.enabled
        }
    }

    func setting(_ enabled: Bool, in o: AdvancedOptions) -> AdvancedOptions {
        var copy = o
        switch self {
        case .resize: copy.resize.enabled = enabled
        case .rotate: copy.rotate.enabled = enabled
        case .crop: copy.crop.enabled = enabled
        case .canvas: copy.canvas.enabled = enabled
        case .colorDepth: copy.colorDepth.enabled = enabled
        case .adjustments: copy.adjustments.enabled = enabled
        case .dpi: copy.dpi.enabled = enabled
        case .text: copy.text.enabled = enabled
        case .watermark: copy.watermark.enabled = enabled
        case .border: copy.border.enabled = enabled
        }
        return copy
    }

    /// Switching a step on also turns on "Aplicar estas etapas", so the switch is never a no-op.
    func applying(_ enabled: Bool, to s: ConvertSettings) -> ConvertSettings {
        var copy = s
        copy.advanced = setting(enabled, in: s.advanced)
        if enabled { copy.useAdvancedOptions = true }
        return copy
    }
}
