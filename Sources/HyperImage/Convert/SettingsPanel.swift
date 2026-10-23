import HyperImageCore
import SwiftUI

/// Right side of the window: options grouped in cards; the summary and main action stay pinned below them.
struct SettingsPanel: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let start: () -> Void

    var body: some View {
        @Bindable var app = app
        let settings = $app.state.convert
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if app.state.showPreview, let item = app.selectedItem { PreviewCard(item: item) }
                switch app.state.convert.mode {
                case .convert, .compress:
                    OutputSection(settings: settings)
                    ReductionSection(settings: settings)
                    AdvancedStepsCard(settings: settings)
                case .upscale:
                    UpscaleSection(settings: settings.upscale)
                case .rename:
                    RenamePanel(settings: $app.state.rename)
                }
                if app.state.convert.mode != .rename { SaveSection(settings: settings) }
            }
            .padding(.horizontal, 16).padding(.vertical, 18)
            .animation(.snappy, value: app.state.convert.mode)
            .disabled(runner.isRunning)
        }
        .scrollIndicators(.visible)
        // Pinned, with its own bar background, so the cards scroll underneath instead of being covered.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // A Divider inside .overlay draws vertically, so the rule is a real stack member.
            VStack(spacing: 0) {
                Divider()
                Group {
                    if app.state.convert.mode == .rename { RenameSummary(start: start) } else { SummaryBox(runner: runner, start: start) }
                }.padding(14)
            }
            .background(.bar)
        }
        .frame(width: 340)
        .background(.background.secondary)
    }
}

// MARK: - Building blocks

struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.08)) }
        }
    }
}

struct ToggleRow: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// Slider with a value label and "smaller file / more quality" ends.
struct QualityRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    var range: ClosedRange<Double> = 1...100

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text("\(value) %").font(.callout.weight(.semibold)).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: range)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text("\(value) %"))
            HStack {
                Text("Menor arquivo")
                Spacer()
                Text("Mais qualidade")
            }
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }
}

/// Number field + stepper + common presets, applied as the user types.
private struct NumberRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let presets: [(String, Int)]

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.callout)
            Spacer()
            TextField(title, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.grouping(.never))
                .labelsHidden()
                .frame(width: 64).multilineTextAlignment(.trailing)
            Stepper(title, value: $value, in: range, step: step).labelsHidden()
            Text(unit).foregroundStyle(.secondary)
            Menu {
                ForEach(presets, id: \.1) { name, preset in Button(name) { value = preset } }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Valores comuns")
            .accessibilityLabel("Valores comuns")
        }
    }
}

// MARK: - Convert / Compress

private struct OutputSection: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings

    var body: some View {
        PanelSection(title: "Saída") {
            if settings.mode == .convert {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Formato de destino").font(.callout.weight(.medium))
                    Picker("Formato de destino", selection: $settings.format) {
                        ForEach(OutputFormat.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                    }
                    .labelsHidden()
                    Text(settings.format.help).font(.caption).foregroundStyle(.secondary)
                }
                if settings.formatSettings.quality(for: settings.format) != nil {
                    QualityRow(title: "Qualidade da imagem", value: Binding(
                        get: { settings.formatSettings.quality(for: settings.format) ?? 80 },
                        set: { settings.formatSettings = settings.formatSettings.with(quality: $0, for: settings.format) }))
                }
                Button("Mais ajustes de \(settings.format.displayName)…") { app.route = .formatSettings }
                    .buttonStyle(.link).font(.caption)
                    .help("⌘,")
            } else {
                Label("Cada imagem mantém o próprio formato.", systemImage: "doc.on.doc")
                    .font(.callout).foregroundStyle(.secondary)
                QualityRow(title: "Qualidade", value: Binding(
                    get: { settings.formatSettings.jpeg.quality },
                    set: { q in
                        settings.formatSettings = [OutputFormat.jpeg, .webp, .heic, .avif, .jpeg2000]
                            .reduce(settings.formatSettings) { $0.with(quality: q, for: $1) }
                    }))
                Text("Vale para JPEG, WebP, HEIC, AVIF e JPEG 2000. PNG, GIF, BMP e TIFF são regravados sem perdas.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ToggleRow(title: "Manter dimensões originais", help: "Não altera largura ou altura.", isOn: $settings.keepDimensions)
            if !settings.keepDimensions {
                NumberRow(title: "Lado maior até", value: $settings.maxLongSide, range: 16...50_000, step: 100, unit: "px",
                          presets: [("1080 px (redes sociais)", 1080), ("1920 px (Full HD)", 1920), ("2400 px", 2400),
                                    ("3840 px (4K)", 3840)])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct ReductionSection: View {
    @Binding var settings: ConvertSettings

    /// The size target only lowers the quality of lossy formats; say so when it cannot apply.
    private var losslessNote: LocalizedStringKey? {
        if settings.mode == .compress {
            return "Em PNG, GIF, BMP e TIFF o limite não se aplica: esses formatos não têm ajuste de qualidade."
        }
        return settings.formatSettings.quality(for: settings.format) == nil
            ? "O formato \(settings.format.displayName) não tem ajuste de qualidade; o limite não se aplica." : nil
    }

    var body: some View {
        PanelSection(title: "Redução de tamanho") {
            ToggleRow(title: "Limitar tamanho do arquivo", help: "Reduz a qualidade até caber no tamanho escolhido.",
                      isOn: $settings.limitFileSize)
            if settings.limitFileSize {
                VStack(alignment: .leading, spacing: 6) {
                    NumberRow(title: "Tamanho máximo", value: $settings.maxFileSizeKB, range: 10...100_000, step: 50, unit: "KB",
                              presets: [("100 KB", 100), ("250 KB", 250), ("500 KB", 500), ("1 MB", 1024), ("2 MB", 2048),
                                        ("5 MB", 5120)])
                    if let note = losslessNote {
                        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider()
            ToggleRow(title: "Preservar transparência", help: "Quando o formato permitir; senão o fundo fica branco.",
                      isOn: $settings.preserveTransparency)
        }
    }
}

// MARK: - AI Upscale

private struct UpscaleSection: View {
    @Binding var settings: UpscaleSettings

    var body: some View {
        PanelSection(title: "Modelo de IA") {
            VStack(spacing: 6) {
                ForEach(UpscaleModel.allCases, id: \.self) { model in
                    let selected = settings.model == model
                    Button { withAnimation(.snappy) { settings.model = model } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.title).font(.callout.weight(.medium))
                                Text(model.help).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        PanelSection(title: "Ampliação") {
            Picker("Escala", selection: $settings.scale) {
                Text("2×").tag(2)
                Text("3×").tag(3)
                Text("4×").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 5) {
                Text("Formato de saída").font(.callout.weight(.medium))
                Picker("Formato de saída", selection: $settings.format) {
                    Text("PNG").tag(UpscaleFormat.png)
                    Text("JPEG").tag(UpscaleFormat.jpeg)
                    Text("WebP").tag(UpscaleFormat.webp)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if settings.format != .png {
                QualityRow(title: "Qualidade", value: Binding(get: { 100 - settings.compression }, set: { settings.compression = 100 - $0 }))
            }
            Label("Usa a GPU do Mac. O tempo restante aparece depois do início.", systemImage: "cpu")
                .font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("Motor de IA: Upscayl (AGPL-3.0) com Real-ESRGAN.")
            Link("Ver código-fonte do motor", destination: URL(string: "https://github.com/upscayl/upscayl-ncnn")!)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.leading, 2)
    }
}

// MARK: - Save

/// One choice instead of two overlapping toggles.
private enum ExistingFilePolicy: Hashable {
    case ask, skip, replace

    init(_ s: ConvertSettings) {
        self = s.skipExisting ? .skip : (s.askBeforeOverwrite ? .ask : .replace)
    }

    func apply(to s: inout ConvertSettings) {
        s.skipExisting = self == .skip
        s.askBeforeOverwrite = self == .ask
    }
}

private struct SaveSection: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings
    @State private var showMore = false

    var body: some View {
        PanelSection(title: "Salvar arquivos") {
            Picker("Destino", selection: $settings.useOutputFolder) {
                Text("Ao lado dos originais").tag(false)
                Text("Em uma pasta").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if settings.useOutputFolder {
                OutputFolderRow(path: $settings.outputFolder)
                if app.hasFolderItems {
                    Toggle("Manter estrutura de pastas", isOn: $settings.keepFolderStructure)
                }
            }
            if settings.mode != .upscale {
                Toggle("Adicionar sufixo ao nome (\(settings.mode == .compress ? "-comprimido" : "-convertido"))", isOn: $settings.addSuffix)
                    .disabled(settings.rename)
                OutputRenameRows(settings: $settings)
            }
            Picker("Se o arquivo já existir", selection: Binding(get: { ExistingFilePolicy(settings) }, set: { $0.apply(to: &settings) })) {
                Text("Perguntar").tag(ExistingFilePolicy.ask)
                Text("Pular").tag(ExistingFilePolicy.skip)
                Text("Substituir").tag(ExistingFilePolicy.replace)
            }
            DisclosureGroup("Mais opções", isExpanded: $showMore) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Extensão em maiúsculas (.JPG)", isOn: $settings.uppercaseExtension)
                    Toggle("Manter data e hora originais", isOn: $settings.keepDates)
                    Toggle("Abrir a lista de erros ao terminar", isOn: $settings.showErrors)
                    if settings.mode != .upscale {
                        Toggle("Processar várias imagens ao mesmo tempo", isOn: $settings.parallel)
                    }
                    Toggle("Abrir a pasta ao concluir", isOn: $settings.openFolderWhenDone)
                }
                .padding(.top, 8)
            }
            .font(.callout.weight(.medium))
        }
        .toggleStyle(.checkbox)
    }
}

extension OutputFormat {
    var menuTitle: String {
        switch self {
        case .jpeg: String(localized: "JPEG — menor tamanho")
        case .webp: String(localized: "WebP — moderno e leve")
        case .png: String(localized: "PNG — sem perdas")
        case .heic: String(localized: "HEIC — padrão da Apple")
        case .avif: String(localized: "AVIF — máxima compressão")
        case .gif: String(localized: "GIF — animações e ícones")
        case .tiff: String(localized: "TIFF — impressão e edição")
        case .bmp: String(localized: "BMP — compatibilidade")
        case .jpeg2000: String(localized: "JPEG 2000")
        case .pdf: String(localized: "PDF — documento")
        }
    }

    var help: LocalizedStringKey {
        switch self {
        case .jpeg: "Ideal para fotografias e imagens compactas."
        case .webp: "Boa qualidade com arquivos menores; ótimo para a web."
        case .png: "Preserva detalhes e transparência, mas gera arquivos maiores."
        case .heic: "Fotos com metade do tamanho de um JPEG, padrão do iPhone."
        case .avif: "Arquivos muito pequenos; nem todos os programas abrem."
        case .gif: "Até 256 cores; use para gráficos simples."
        case .tiff: "Sem perdas, aceito por gráficas e editores."
        case .bmp: "Sem compressão; para programas antigos."
        case .jpeg2000: "Compressão avançada usada em arquivos e medicina."
        case .pdf: "Cada imagem vira um documento PDF."
        }
    }
}

private struct OutputFolderRow: View {
    @Binding var path: String

    var body: some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(path.isEmpty ? String(localized: "Nenhuma pasta escolhida") : (path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1).truncationMode(path.isEmpty ? .tail : .head)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
                .help(path)
            Spacer()
            Button(path.isEmpty ? "Escolher…" : "Alterar…") {
                if let url = FilePanels.chooseFolder(startingAt: path) { path = url.path }
            }
            Button("Abrir no Finder", systemImage: "arrow.up.forward.app") {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
            .labelStyle(.iconOnly)
            .disabled(path.isEmpty)
        }
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
