import HyperImageCore
import SwiftUI

/// Converter: the destination format comes first and the quality stays at its best unless the user asks otherwise.
struct ConvertSections: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings

    var body: some View {
        Section {
            FormatGrid(format: $settings.format)
            OtherFormatsRow(format: $settings.format)
            if let hint = HEICHint(inputs: app.inputs, format: settings.format) {
                hint.view { withAnimation(.snappy) { settings.format = .jpeg } }
                    .transition(.blurReplace)
            }
            if settings.format.supportsTransparency {
                Toggle("Manter transparência", isOn: $settings.preserveTransparency)
                    .transition(.blurReplace)
            }
            LabeledContent("Ajustes de \(settings.format.displayName)") {
                Button("Mais ajustes…") { app.route = .formatSettings }
                    .help("⌘,")
            }
        } header: {
            Text("Formato")
        } footer: {
            Text(settings.format.help)
        }
        if hasQuality {
            QualityChoice(settings: $settings)
        }
        Section {
            ToggleRow(title: "Manter dimensões originais", help: "Não altera largura ou altura.", isOn: $settings.keepDimensions.animation(.snappy))
            if !settings.keepDimensions {
                NumberRow(title: "Lado maior até", value: $settings.maxLongSide, range: 16...50_000, step: 100, unit: "px",
                          presets: [("1080 px (redes sociais)", 1080), ("1920 px (Full HD)", 1920), ("2400 px", 2400),
                                    ("3840 px (4K)", 3840)])
                    .transition(.blurReplace)
            }
        } header: {
            Text("Dimensões")
        }
        AdvancedStepsSection(settings: $settings)
        SaveSection(settings: $settings)
    }

    private var hasQuality: Bool { settings.formatSettings.quality(for: settings.format) != nil }
}

/// Full quality by default; lowering it is an explicit, secondary choice.
private struct QualityChoice: View {
    @Binding var settings: ConvertSettings

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { !settings.fullQuality }, set: { settings.fullQuality = !$0 }).animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reduzir a qualidade")
                    Text(settings.fullQuality ? "Desligado: as imagens mantêm a qualidade máxima." : "Arquivos menores, com alguma perda.")
                        .font(.callout).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }
            if !settings.fullQuality {
                QualityRow(title: "Qualidade", value: Binding(
                    get: { settings.formatSettings.quality(for: settings.format) ?? 80 },
                    set: { settings.formatSettings = settings.formatSettings.with(quality: $0, for: settings.format) }))
                    .transition(.blurReplace)
            }
        } header: {
            Text("Qualidade")
        } footer: {
            if settings.fullQuality {
                Text("Converter muda só o formato. Para diminuir o tamanho dos arquivos, use Comprimir.")
            }
        }
    }
}
