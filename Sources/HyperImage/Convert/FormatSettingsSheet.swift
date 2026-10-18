import HyperImageCore
import SwiftUI

/// Per-format encoder options, edited on a draft and applied with OK.
struct FormatSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FormatSettings()
    @State private var format = OutputFormat.jpeg

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Ajustes de \(format.displayName)") { fields }
            }
            .formStyle(.grouped)
            HStack {
                Button("Restaurar Padrões") { draft = draft.resetting(format) }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    app.state.convert.formatSettings = draft
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear {
            draft = app.state.convert.formatSettings
            format = app.state.convert.format
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch format {
        case .jpeg:
            QualitySlider(title: "Qualidade", value: $draft.jpeg.quality)
            Toggle("Usar a qualidade do arquivo original quando possível", isOn: $draft.jpeg.useOriginalQuality)
            Picker("Fotométrico", selection: $draft.jpeg.photometric) {
                Text("(Sem alteração)").tag(JPEGPhotometric.noChange)
                Text("RGB").tag(JPEGPhotometric.rgb)
                Text("Tons de cinza").tag(JPEGPhotometric.grayscale)
                Text("YCbCr").tag(JPEGPhotometric.ycbcr)
                Text("CMYK").tag(JPEGPhotometric.cmyk)
            }
            Picker("Subamostragem de cor", selection: $draft.jpeg.subsampling) {
                Text("Desativada (melhor qualidade)").tag(JPEGSubsampling.none)
                Text("Média").tag(JPEGSubsampling.medium)
                Text("Alta (arquivo menor)").tag(JPEGSubsampling.high)
            }
            .disabled(draft.jpeg.photometric == .cmyk || draft.jpeg.photometric == .grayscale || draft.jpeg.photometric == .rgb)
            LabeledContent("Suavização") {
                HStack(spacing: 6) {
                    Text("\(draft.jpeg.smoothing)").monospacedDigit()
                    Stepper("Suavização", value: $draft.jpeg.smoothing, in: JPEGSettings.smoothingRange).labelsHidden()
                }
            }
            .disabled(draft.jpeg.photometric == .cmyk)
            Toggle("Otimizar tabela de Huffman", isOn: $draft.jpeg.optimizeHuffman)
                .disabled(draft.jpeg.photometric == .cmyk)
            Toggle("Progressivo", isOn: $draft.jpeg.progressive)
            Toggle("Manter dados EXIF / IPTC", isOn: $draft.jpeg.keepMetadata)
        case .bmp:
            PalettePicker(selection: $draft.bmp.colors, options: BMPSettings.allowedColors)
        case .gif:
            PalettePicker(selection: $draft.gif.colors, options: PaletteSize.allCases.filter { $0 != .trueColor })
            Toggle("Manter transparência", isOn: $draft.gif.transparent)
        case .png:
            PalettePicker(selection: $draft.png.colors, options: PNGSettings.allowedColors)
            Toggle("Entrelaçado", isOn: $draft.png.interlaced)
        case .jpeg2000:
            QualitySlider(title: "Qualidade (100 = sem perdas)", value: $draft.jpeg2000.quality)
            Picker("Fotométrico", selection: $draft.jpeg2000.photometric) {
                Text("RGB").tag(JPEG2000Photometric.rgb)
                Text("Tons de cinza").tag(JPEG2000Photometric.grayscale)
            }
        case .tiff:
            Picker("Compressão", selection: $draft.tiff.compression) {
                Text("Sem compressão").tag(TIFFCompression.none)
                Text("LZW").tag(TIFFCompression.lzw)
                Text("PackBits").tag(TIFFCompression.packBits)
            }
            Picker("Fotométrico", selection: $draft.tiff.photometric) {
                Text("(Sem alteração)").tag(TIFFPhotometric.noChange)
                Text("RGB").tag(TIFFPhotometric.rgb)
                Text("Paleta (256 cores)").tag(TIFFPhotometric.palette256)
                Text("CMYK").tag(TIFFPhotometric.cmyk)
                Text("Tons de cinza").tag(TIFFPhotometric.grayscale)
            }
        case .pdf:
            Picker("Qualidade", selection: $draft.pdf.quality) {
                ForEach(PDFQuality.allCases, id: \.self) { q in
                    switch q {
                    case .lossless: Text("Sem perdas").tag(q)
                    case .blackWhite: Text("Preto e branco").tag(q)
                    default: Text("\(q.rawValue)").tag(q)
                    }
                }
            }
            Picker("DPI da página", selection: $draft.pdf.useOriginalDPI) {
                Text("Do arquivo original").tag(true)
                Text("Tela (72 dpi)").tag(false)
            }
        case .webp:
            Picker("Compressão", selection: $draft.webp.lossless) {
                Text("Com perdas").tag(false)
                Text("Sem perdas").tag(true)
            }
            .pickerStyle(.segmented)
            if !draft.webp.lossless {
                QualitySlider(title: "Qualidade", value: $draft.webp.quality)
                Toggle("Sharp YUV (mais qualidade nas cores)", isOn: $draft.webp.sharpYUV)
            }
        case .heic:
            QualitySlider(title: "Qualidade", value: $draft.heic.quality)
            Toggle("Manter dados EXIF / IPTC / GPS", isOn: $draft.heic.keepMetadata)
        case .avif:
            QualitySlider(title: "Qualidade", value: $draft.avif.quality)
        }
    }
}

struct QualitySlider: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: 0...100)
                TextField("", value: $value, format: .number)
                    .frame(width: 48)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: value) { _, v in value = min(100, max(0, v)) }
            }
        }
    }
}

private struct PalettePicker: View {
    @Binding var selection: PaletteSize
    let options: [PaletteSize]

    var body: some View {
        Picker("Cores", selection: $selection) {
            ForEach(options, id: \.self) { size in
                switch size {
                case .trueColor: Text("24 bits (16,7 milhões)").tag(size)
                case .blackWhite: Text("Preto e branco").tag(size)
                default: Text("\(size.rawValue) cores").tag(size)
                }
            }
        }
        .onAppear { if !options.contains(selection) { selection = options[0] } }
    }
}
