import HyperImageCore
import SwiftUI

struct AdjustmentsStepView: View {
    @Binding var o: AdjustmentOptions

    var body: some View {
        Section("Tom") {
            AdjustmentSlider(title: "Brilho", value: $o.brightness, range: -255...255)
            AdjustmentSlider(title: "Contraste", value: $o.contrast, range: -100...100)
            AdjustmentSlider(title: "Gama", value: $o.gamma, range: 0.01...10, neutral: 1, decimals: 2)
            AdjustmentSlider(title: "Sombras", value: $o.shadows, range: -100...100)
            AdjustmentSlider(title: "Realces", value: $o.highlights, range: -100...100)
        }
        Section("Cor") {
            AdjustmentSlider(title: "Matiz", value: $o.hue, range: -180...180)
            AdjustmentSlider(title: "Saturação", value: $o.saturation, range: -100...100)
            AdjustmentSlider(title: "Luminosidade", value: $o.lightness, range: -100...100)
            AdjustmentSlider(title: "Vermelho", value: $o.red, range: -255...255)
            AdjustmentSlider(title: "Verde", value: $o.green, range: -255...255)
            AdjustmentSlider(title: "Azul", value: $o.blue, range: -255...255)
        }
        Section("Nitidez") {
            AdjustmentSlider(title: "Nitidez (negativo suaviza)", value: $o.sharpen, range: -100...100)
            Toggle("Máscara de nitidez (USM)", isOn: $o.unsharpMask)
            if o.unsharpMask {
                AdjustmentSlider(title: "Raio", value: $o.unsharpRadius, range: 0.1...10, neutral: 1, decimals: 1)
            }
        }
        Section("Efeitos") {
            Toggle("Tons de cinza", isOn: $o.grayscale)
            Toggle("Negativo", isOn: $o.negative)
            Toggle("Sépia", isOn: $o.sepia)
            Toggle("Aplicar ajustes ANTES de redimensionar", isOn: $o.beforeResize)
            Button("Zerar Ajustes") { o = o.neutralized() }
                .disabled(o.isIdentity)
        }
    }
}
