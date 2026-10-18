import HyperImageCore
import SwiftUI

struct RotateStepView: View {
    @Binding var o: RotateOptions

    var body: some View {
        Section {
            Toggle("Espelhar horizontalmente", isOn: $o.flipHorizontal)
            Toggle("Espelhar verticalmente", isOn: $o.flipVertical)
        }
        Section {
            Toggle("Girar", isOn: $o.rotate)
            Picker("Ângulo", selection: $o.angle) {
                Label("90° anti-horário", systemImage: "rotate.left").tag(RotationAngle.counterClockwise90)
                Label("90° horário", systemImage: "rotate.right").tag(RotationAngle.clockwise90)
                Label("180°", systemImage: "arrow.2.circlepath").tag(RotationAngle.halfTurn)
            }
            .pickerStyle(.radioGroup)
            .disabled(!o.rotate)
        }
    }
}

struct CropStepView: View {
    @Binding var o: CropOptions

    var body: some View {
        Section {
            Picker("Modo", selection: $o.mode) {
                Text("Em pixels").tag(CropMode.pixels)
                Text("Tamanho de impressão").tag(CropMode.printSize)
                Text("Proporção").tag(CropMode.aspectRatio)
            }
        }
        Section {
            switch o.mode {
            case .pixels:
                IntField(title: "Largura", value: $o.width, range: 1...100_000, suffix: "px")
                IntField(title: "Altura", value: $o.height, range: 1...100_000, suffix: "px")
                StandardSizeMenu(sizes: StandardSizes.cropAndCanvas) { o.width = $0.width; o.height = $0.height }
            case .printSize:
                DecimalField(title: "Largura", value: $o.printWidth, step: 0.5, range: 0.01...1000)
                DecimalField(title: "Altura", value: $o.printHeight, step: 0.5, range: 0.01...1000)
                UnitPicker(unit: $o.printUnit)
                Text("Usa o DPI gravado em cada imagem.").font(.caption).foregroundStyle(.secondary)
            case .aspectRatio:
                DecimalField(title: "Largura", value: $o.ratioWidth, step: 1, range: 0.01...1000)
                DecimalField(title: "Altura", value: $o.ratioHeight, step: 1, range: 0.01...1000)
                Menu("Proporções comuns") {
                    ForEach([(1.0, 1.0), (4, 3), (3, 2), (16, 9), (5, 4), (21, 9)], id: \.0) { r in
                        Button("\(Int(r.0)):\(Int(r.1))") { o.ratioWidth = r.0; o.ratioHeight = r.1 }
                    }
                }
                .fixedSize()
            }
        }
        Section {
            Toggle("Inverter largura e altura para casar os lados maiores", isOn: $o.switchToMatchLongSides)
            if o.mode == .pixels {
                Toggle("Definir coordenada X-Y (canto superior esquerdo)", isOn: $o.useOrigin)
                if o.useOrigin {
                    IntField(title: "X", value: $o.originX, suffix: "px")
                    IntField(title: "Y", value: $o.originY, suffix: "px")
                } else {
                    Text("Sem coordenadas, o recorte é centralizado.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CanvasStepView: View {
    @Binding var o: CanvasOptions

    var body: some View {
        Section {
            Picker("Modo", selection: $o.mode) {
                Text("Em pixels").tag(CanvasMode.pixels)
                Text("Em porcentagem").tag(CanvasMode.percentage)
                Text("Expandir (adicionar espaço)").tag(CanvasMode.expand)
            }
        }
        Section {
            switch o.mode {
            case .pixels:
                IntField(title: "Largura da tela", value: $o.width, range: 1...100_000, suffix: "px")
                IntField(title: "Altura da tela", value: $o.height, range: 1...100_000, suffix: "px")
                StandardSizeMenu(sizes: StandardSizes.cropAndCanvas) { o.width = $0.width; o.height = $0.height }
                alignment
            case .percentage:
                DecimalField(title: "Largura", value: $o.percentWidth, step: 5, range: 1...1000, suffix: "%")
                DecimalField(title: "Altura", value: $o.percentHeight, step: 5, range: 1...1000, suffix: "%")
                alignment
            case .expand:
                Picker("Unidade", selection: $o.expandUnit) {
                    Text("Pixels").tag(CanvasExpandUnit.pixels)
                    Text("Porcentagem").tag(CanvasExpandUnit.percentage)
                }
                .pickerStyle(.segmented)
                let suffix = o.expandUnit == .pixels ? "px" : "%"
                DecimalField(title: "Espaço horizontal", value: $o.expandHorizontal, step: 1, range: 0...100_000, suffix: suffix)
                Picker("Lado", selection: $o.horizontalSide) {
                    Text("Esquerda").tag(HorizontalExpandSide.left)
                    Text("Direita").tag(HorizontalExpandSide.right)
                    Text("Ambos").tag(HorizontalExpandSide.both)
                }
                .pickerStyle(.segmented)
                DecimalField(title: "Espaço vertical", value: $o.expandVertical, step: 1, range: 0...100_000, suffix: suffix)
                Picker("Lado", selection: $o.verticalSide) {
                    Text("Topo").tag(VerticalExpandSide.top)
                    Text("Base").tag(VerticalExpandSide.bottom)
                    Text("Ambos").tag(VerticalExpandSide.both)
                }
                .pickerStyle(.segmented)
                Text("O valor é adicionado em cada lado escolhido.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section {
            ColorRow(title: "Cor de fundo", color: $o.background)
            Toggle("Inverter valores em imagens retrato", isOn: $o.switchForPortrait)
        }
    }

    @ViewBuilder
    private var alignment: some View {
        Picker("Alinhamento horizontal", selection: $o.horizontalAlignment) {
            Text("Esquerda").tag(HorizontalAlignment.left)
            Text("Centro").tag(HorizontalAlignment.center)
            Text("Direita").tag(HorizontalAlignment.right)
        }
        Picker("Alinhamento vertical", selection: $o.verticalAlignment) {
            Text("Topo").tag(VerticalAlignment.top)
            Text("Centro").tag(VerticalAlignment.center)
            Text("Base").tag(VerticalAlignment.bottom)
        }
    }
}

struct ColorDepthStepView: View {
    @Binding var o: ColorDepthOptions

    var body: some View {
        Section {
            Picker("Cores", selection: $o.depth) {
                ForEach(ColorDepth.allCases, id: \.self) { depth in
                    if let count = depth.colorCount {
                        Text("\(count) cores (\(depth.rawValue) bits)").tag(depth)
                    } else {
                        Text("16,7 milhões (24 bits)").tag(depth)
                    }
                }
            }
            .pickerStyle(.radioGroup)
            Text("Redução sem pontilhamento; 2 cores = limiar preto e branco.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DPIStepView: View {
    @Binding var o: DPIOptions

    var body: some View {
        Section {
            DecimalField(title: "DPI horizontal", value: $o.x, step: 1, range: 1...10_000)
            DecimalField(title: "DPI vertical", value: $o.y, step: 1, range: 1...10_000)
            Menu("Valores comuns") {
                ForEach(StandardSizes.printDPIs, id: \.self) { dpi in Button("\(Int(dpi)) DPI") { o.x = dpi; o.y = dpi } }
            }
            .fixedSize()
            Text("Só altera o metadado de resolução; os pixels não mudam.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
