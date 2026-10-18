import HyperImageCore

enum AdvancedStep: String, CaseIterable, Codable, Identifiable {
    case resize, rotate, crop, canvas, colorDepth, adjustments, dpi, text, watermark, border

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resize: "Redimensionar"
        case .rotate: "Girar / Espelhar"
        case .crop: "Recortar"
        case .canvas: "Tamanho da Tela"
        case .colorDepth: "Profundidade de Cor"
        case .adjustments: "Ajustes"
        case .dpi: "DPI"
        case .text: "Texto"
        case .watermark: "Marca d'Água"
        case .border: "Bordas"
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
}
