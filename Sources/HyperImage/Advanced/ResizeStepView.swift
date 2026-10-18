import HyperImageCore
import SwiftUI

struct ResizeStepView: View {
    @Binding var o: ResizeOptions
    @Binding var presets: [PixelSize]
    @State private var editingPresets = false

    var body: some View {
        Section {
            Picker("Modo", selection: $o.mode) {
                Text("Em pixels").tag(ResizeMode.pixels)
                Text("Em porcentagem").tag(ResizeMode.percentage)
                Text("Tamanho de impressão").tag(ResizeMode.printSize)
                Text("Com base em um lado").tag(ResizeMode.oneSide)
            }
        }
        Section { modeFields }
        Section("Filtro") {
            Picker("Filtro de reamostragem", selection: $o.filter) {
                ForEach(ResizeFilter.allCases, id: \.self) { Text(Self.filterName($0)).tag($0) }
            }
        }
        if o.mode == .pixels || o.mode == .printSize {
            Section("Proporção") {
                Toggle("Inverter largura e altura para casar os lados maiores", isOn: $o.switchToMatchLongSides)
                Toggle("Preservar proporção", isOn: $o.preserveAspectRatio)
                if o.preserveAspectRatio {
                    Toggle("Recorte inteligente (tamanho exato, corta o excesso)", isOn: $o.smartCropping)
                        .onChange(of: o.smartCropping) { _, on in if on { o.smartFilling = false } }
                    Toggle("Preenchimento inteligente (tamanho exato, completa com cor)", isOn: $o.smartFilling)
                        .onChange(of: o.smartFilling) { _, on in if on { o.smartCropping = false } }
                    if o.smartFilling { ColorRow(title: "Cor de preenchimento", color: $o.fillColor) }
                }
            }
        }
        Section {
            Toggle("Não redimensionar se a imagem já for menor", isOn: $o.onlyIfLarger)
        }
        .sheet(isPresented: $editingPresets) {
            ListEditorSheet(title: "Tamanhos padrão", items: $presets, defaults: StandardSizes.resize, newItem: PixelSize(width: 800, height: 600)) { $size in
                HStack {
                    TextField("Largura", value: $size.width, format: .number.grouping(.never)).frame(width: 70)
                    Text("×")
                    TextField("Altura", value: $size.height, format: .number.grouping(.never)).frame(width: 70)
                }
            }
        }
    }

    @ViewBuilder
    private var modeFields: some View {
        switch o.mode {
        case .pixels:
            IntField(title: "Largura", value: $o.width, range: 1...100_000, suffix: "px")
            IntField(title: "Altura", value: $o.height, range: 1...100_000, suffix: "px")
            StandardSizeMenu(sizes: presets, editList: { editingPresets = true }) { o.width = $0.width; o.height = $0.height }
        case .percentage:
            DecimalField(title: "Porcentagem", value: $o.percentage, step: 5, range: 0.1...10_000, suffix: "%")
            Menu("Porcentagens comuns") {
                ForEach(StandardSizes.percentages, id: \.self) { p in Button("\(Int(p)) %") { o.percentage = p } }
            }
            .fixedSize()
        case .printSize:
            DecimalField(title: "Largura", value: $o.printWidth, step: 0.5, range: 0.01...1000)
            DecimalField(title: "Altura", value: $o.printHeight, step: 0.5, range: 0.01...1000)
            UnitPicker(unit: $o.printUnit)
            Picker("Resolução", selection: $o.printDPI) {
                ForEach(StandardSizes.printDPIs, id: \.self) { Text("\(Int($0)) DPI").tag($0) }
            }
        case .oneSide:
            Picker("Lado", selection: $o.side) {
                Text("Largura").tag(ResizeSide.width)
                Text("Altura").tag(ResizeSide.height)
                Text("Lado maior").tag(ResizeSide.longSide)
                Text("Lado menor").tag(ResizeSide.shortSide)
            }
            IntField(title: "Exatamente", value: $o.sideLength, range: 1...100_000, suffix: "px")
            Menu("Medidas comuns") {
                ForEach(StandardSizes.sideLengths, id: \.self) { n in Button("\(n) px") { o.sideLength = n } }
            }
            .fixedSize()
            Text("A proporção é sempre preservada.").font(.caption).foregroundStyle(.secondary)
        }
    }

    static func filterName(_ filter: ResizeFilter) -> String {
        switch filter {
        case .none: String(localized: "Nenhum")
        case .bell: String(localized: "Bell")
        case .bicubic: String(localized: "Bicúbico")
        case .bilinear: String(localized: "Bilinear")
        case .bspline: String(localized: "B-Spline")
        case .fastLinear: String(localized: "Linear rápido")
        case .lanczos2: String(localized: "Lanczos2 (mais nítido)")
        case .lanczos3: String(localized: "Lanczos3 (padrão)")
        case .linear: String(localized: "Linear")
        case .mitchell: String(localized: "Mitchell")
        case .nearest: String(localized: "Vizinho mais próximo")
        case .triangle: String(localized: "Triângulo")
        }
    }
}

struct UnitPicker: View {
    @Binding var unit: LengthUnit

    var body: some View {
        Picker("Unidade", selection: $unit) {
            Text("polegadas").tag(LengthUnit.inch)
            Text("cm").tag(LengthUnit.centimeter)
        }
        .pickerStyle(.segmented)
    }
}
