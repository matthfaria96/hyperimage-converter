import AppKit
import HyperImageCore
import SwiftUI

struct TextStepView: View {
    @Binding var o: TextOptions
    private static let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Section("Texto") {
            TextEditor(text: $o.text)
                .font(.body.monospaced())
                .frame(minHeight: 70)
            HStack {
                Menu("Inserir Variável") {
                    ForEach(TextVariables.catalog, id: \.token) { v in
                        Button("\(v.title)  \(v.token)") { o.text += v.token }
                    }
                }
                .fixedSize()
                Spacer()
                Picker("Alinhamento", selection: $o.alignment) {
                    Image(systemName: "text.alignleft").tag(HorizontalAlignment.left)
                    Image(systemName: "text.aligncenter").tag(HorizontalAlignment.center)
                    Image(systemName: "text.alignright").tag(HorizontalAlignment.right)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Text("Sem EXIF, as variáveis de data da foto usam a data do arquivo.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Fonte") {
            Picker("Família", selection: $o.fontFamily) {
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
            }
            DecimalField(title: "Tamanho", value: $o.fontSize, step: 1, range: 4...1000, suffix: "px")
            Toggle("Negrito", isOn: $o.bold)
            Toggle("Itálico", isOn: $o.italic)
            ColorRow(title: "Cor do texto", color: $o.color)
            Toggle("Sombra", isOn: $o.shadow)
            Toggle("Fundo", isOn: $o.background)
            if o.background {
                ColorRow(title: "Cor do fundo", color: $o.backgroundColor)
                Toggle("Cantos arredondados", isOn: $o.roundedBackground)
            }
        }
        Section("Posição") {
            PositionPicker(position: $o.position)
            IntField(title: "Deslocamento X", value: $o.offsetX, range: -10_000...10_000, suffix: "px")
            IntField(title: "Deslocamento Y", value: $o.offsetY, range: -10_000...10_000, suffix: "px")
            AdjustmentSlider(title: "Opacidade", value: $o.opacity, range: 0...100, neutral: 100)
        }
    }
}

struct WatermarkStepView: View {
    @Binding var o: WatermarkOptions

    var body: some View {
        Section("Imagem") {
            HStack {
                Text(o.imagePath.isEmpty ? "Nenhuma imagem" : (o.imagePath as NSString).lastPathComponent)
                    .foregroundStyle(o.imagePath.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle).help(o.imagePath)
                Spacer()
                Button("Escolher…") { if let url = FilePanels.chooseImage() { o.imagePath = url.path } }
            }
            Text("Use um PNG com transparência para melhores resultados.").font(.caption).foregroundStyle(.secondary)
            AdjustmentSlider(title: "Largura (% da imagem, 0 = original)", value: $o.relativeWidth, range: 0...100)
            Toggle("Sombra", isOn: $o.shadow)
            Toggle("Cantos arredondados", isOn: $o.roundedCorners)
        }
        Section("Posição") {
            PositionPicker(position: $o.position)
            IntField(title: "Deslocamento X", value: $o.offsetX, range: -10_000...10_000, suffix: "px")
            IntField(title: "Deslocamento Y", value: $o.offsetY, range: -10_000...10_000, suffix: "px")
            AdjustmentSlider(title: "Opacidade", value: $o.opacity, range: 0...100, neutral: 100)
        }
    }
}

struct BorderStepView: View {
    @Binding var o: BorderOptions

    var body: some View {
        Section("Molduras (de fora para dentro)") {
            frame("Moldura 1", $o.frame1)
            frame("Moldura 2", $o.frame2)
            frame("Moldura 3", $o.frame3)
        }
        Section("Moldura interna") {
            Toggle("Moldura interna", isOn: $o.innerFrame.enabled)
            if o.innerFrame.enabled {
                IntField(title: "Distância", value: $o.innerFrame.distance, range: 0...10_000, suffix: "px")
                IntField(title: "Espessura", value: $o.innerFrame.width, range: 1...1000, suffix: "px")
                ColorRow(title: "Cor da linha", color: $o.innerFrame.color)
                ColorRow(title: "Cor do preenchimento", color: $o.innerFrame.fillColor)
                AdjustmentSlider(title: "Opacidade do preenchimento", value: $o.innerFrame.fillOpacity, range: 0...100)
            }
        }
        Section("Sombra") {
            Toggle("Sombra", isOn: $o.shadow.enabled)
            if o.shadow.enabled {
                IntField(title: "Raio", value: $o.shadow.radius, range: 0...200)
                IntField(title: "Profundidade", value: $o.shadow.depth, range: 0...200)
                ColorRow(title: "Fundo", color: $o.shadow.background)
                ColorRow(title: "Cor da sombra", color: $o.shadow.color)
            }
            Button("Restaurar Padrões") { o = BorderOptions().with(enabled: o.enabled) }
        }
    }

    private func frame(_ title: String, _ binding: Binding<FrameLine>) -> some View {
        HStack {
            Toggle(title, isOn: binding.enabled)
            Spacer()
            TextField("", value: binding.width, format: .number).frame(width: 48).multilineTextAlignment(.trailing)
                .disabled(!binding.wrappedValue.enabled)
            Text("px").foregroundStyle(.secondary)
            ColorPicker("", selection: Binding(get: { binding.wrappedValue.color.cgColor }, set: { binding.wrappedValue.color = RGBAColor(cgColor: $0) }))
                .labelsHidden()
                .disabled(!binding.wrappedValue.enabled)
        }
    }
}

private extension BorderOptions {
    func with(enabled: Bool) -> BorderOptions {
        var copy = self
        copy.enabled = enabled
        return copy
    }
}
