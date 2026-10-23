import HyperImageCore
import SwiftUI

/// Comprimir: each file keeps its format; the user picks how much to compress and sees the result before running.
struct CompressSections: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings
    let estimate: Estimate?
    let hasInputs: Bool

    var body: some View {
        Section {
            CompressPreview(estimate: estimate, hasInputs: hasInputs)
            if hasInputs {
                Button("Comparar antes e depois…", systemImage: "rectangle.split.2x1") {
                    if let url = app.previewTarget { app.route = .conversionPreview(url) }
                }
                .buttonStyle(.borderless)
                .help("Ver a imagem selecionada (ou a primeira) comprimida, lado a lado com a original (barra de espaço)")
                .transition(.blurReplace)
            }
        } footer: {
            if hasInputs { Text("Estimativa a partir de até 3 imagens da lista.") }
        }
        Section {
            Picker("Nível", selection: levelBinding) {
                Text("Sem perdas").tag(CompressionLevel?.some(.lossless))
                Text("Leve").tag(CompressionLevel?.some(.light))
                Text("Equilibrada").tag(CompressionLevel?.some(.balanced))
                Text("Forte").tag(CompressionLevel?.some(.strong))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            QualityRow(title: "Qualidade", value: $settings.compressQuality.animation(.snappy), range: 10...100)
        } header: {
            Text("Compressão")
        } footer: {
            Text(levelHelp)
                .contentTransition(.opacity)
                .animation(.snappy, value: settings.compressQuality)
        }
        Section {
            ToggleRow(title: "Remover localização e dados da câmera", help: "Tira GPS, EXIF e IPTC: arquivos menores e sem revelar onde a foto foi feita.",
                      isOn: $settings.stripMetadata)
            ToggleRow(title: "Tamanho máximo por arquivo", help: "Baixa mais a qualidade só dos arquivos que passarem do limite.",
                      isOn: $settings.limitFileSize.animation(.snappy))
            if settings.limitFileSize {
                NumberRow(title: "Até", value: $settings.maxFileSizeKB, range: 10...100_000, step: 50, unit: "KB",
                          presets: [("100 KB", 100), ("250 KB", 250), ("500 KB", 500), ("1 MB", 1024), ("2 MB", 2048),
                                    ("5 MB", 5120)])
                    .transition(.blurReplace)
            }
        } footer: {
            Text("Cada imagem mantém o próprio formato e nunca fica maior que o original. PSD, RAW e outros formatos que o Mac não grava são ignorados.")
        }
    }

    private var levelBinding: Binding<CompressionLevel?> {
        Binding(get: { CompressionLevel.matching(settings.compressQuality) },
                set: { level in if let level { withAnimation(.snappy) { settings.compressQuality = level.quality } } })
    }

    private var levelHelp: LocalizedStringKey {
        switch CompressionLevel.matching(settings.compressQuality) {
        case .lossless?: "Sem perdas: nenhum pixel muda; o JPEG é reorganizado e os dados extras saem."
        case .light?: "Leve: quase sem diferença visível, arquivos um pouco menores."
        case .balanced?: "Equilibrada: boa economia sem perda perceptível na maioria das fotos."
        case .strong?: "Forte: arquivos bem menores; detalhes finos podem suavizar."
        case nil: "Qualidade personalizada: \(settings.compressQuality) %."
        }
    }
}

/// Before → after sizes for the whole list, drawn as two bars with the savings in large type.
private struct CompressPreview: View {
    let estimate: Estimate?
    let hasInputs: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(savingsText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(savings > 0 ? Color.green : .secondary)
                    .contentTransition(.numericText(value: Double(savings)))
                Text(hasInputs ? (savings >= 0 ? "menor" : "maior") : "")
                    .font(.title3).foregroundStyle(.secondary)
                Spacer()
            }
            .redacted(reason: hasInputs && estimate?.bytes == nil ? .placeholder : [])
            bar(label: "Antes", bytes: original, fraction: 1, tint: Color.secondary.opacity(0.35))
            bar(label: "Depois", bytes: compressed, fraction: fraction, tint: .accentColor)
        }
        .padding(.vertical, 6)
        .animation(.snappy, value: estimate?.bytes)
        .accessibilityElement(children: .combine)
    }

    private var original: Int64? { hasInputs ? estimate?.originalBytes : nil }
    private var compressed: Int64? { hasInputs ? estimate?.bytes : nil }
    private var fraction: Double {
        guard let original, let compressed, original > 0 else { return hasInputs ? 0.6 : 0 }
        return min(1, max(0.02, Double(compressed) / Double(original)))
    }
    private var savings: Int {
        guard let original, let compressed, original > 0 else { return 0 }
        return Int((Double(original - compressed) / Double(original) * 100).rounded())
    }
    private var savingsText: String {
        guard hasInputs else { return String(localized: "Adicione imagens") }
        return "\(abs(savings)) %"
    }

    private func bar(label: LocalizedStringKey, bytes: Int64?, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(bytes.map(formatBytes) ?? "—").font(.callout.weight(.medium)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule().fill(tint).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }
}
