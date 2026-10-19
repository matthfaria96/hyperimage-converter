import HyperImageCore
import SwiftUI

/// Right side of the window: options grouped in cards, then the summary and the main action.
struct SettingsPanel: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let open: (SheetRoute) -> Void
    let start: () -> Void

    var body: some View {
        @Bindable var app = app
        let settings = $app.state.convert
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch app.state.convert.mode {
                    case .convert, .compress:
                        OutputSection(settings: settings, open: open)
                        ReductionSection(settings: settings)
                    case .upscale:
                        UpscaleSection(settings: settings.upscale)
                    }
                    SaveSection(settings: settings, open: open)
                }
                .padding(.horizontal, 16).padding(.vertical, 18)
                .animation(.snappy, value: app.state.convert.mode)
                .disabled(runner.isRunning)
            }
            Divider()
            SummaryBox(runner: runner, start: start)
                .padding(16)
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
            HStack {
                Text("Menor arquivo")
                Spacer()
                Text("Mais qualidade")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Convert / Compress

private struct OutputSection: View {
    @Binding var settings: ConvertSettings
    let open: (SheetRoute) -> Void

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
                Button("Mais ajustes de \(settings.format.displayName)…") { open(.formatSettings) }
                    .buttonStyle(.link).font(.caption)
            } else {
                Label("Cada imagem mantém o próprio formato.", systemImage: "doc.on.doc")
                    .font(.callout).foregroundStyle(.secondary)
                QualityRow(title: "Qualidade (JPEG, WebP, HEIC, AVIF)", value: Binding(
                    get: { settings.formatSettings.jpeg.quality },
                    set: { q in
                        settings.formatSettings = [OutputFormat.jpeg, .webp, .heic, .avif, .jpeg2000]
                            .reduce(settings.formatSettings) { $0.with(quality: q, for: $1) }
                    }))
            }
            Divider()
            ToggleRow(title: "Manter dimensões originais", help: "Não altera largura ou altura.", isOn: $settings.keepDimensions)
            if !settings.keepDimensions {
                HStack {
                    Text("Lado maior até").font(.callout)
                    Spacer()
                    TextField("", value: Binding(get: { settings.maxLongSide }, set: { settings.maxLongSide = min(max($0, 16), 50_000) }),
                              format: .number.grouping(.never))
                        .frame(width: 70).multilineTextAlignment(.trailing)
                    Text("px").foregroundStyle(.secondary)
                }
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
            ToggleRow(title: "Limitar tamanho do arquivo", help: "Tenta atingir um peso máximo (formatos com perdas).",
                      isOn: $settings.limitFileSize)
            if settings.limitFileSize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tamanho máximo").font(.callout.weight(.medium))
                        Spacer()
                        Text(formatBytes(Int64(settings.maxFileSizeKB) * 1024)).font(.callout.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: Binding(get: { Double(settings.maxFileSizeKB) }, set: { settings.maxFileSizeKB = Int($0) }),
                           in: 50...5000, step: 50)
                        .controlSize(.small)
                    if let note = losslessNote {
                        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider()
            ToggleRow(title: "Preservar transparência", help: "Quando o formato permitir.", isOn: $settings.preserveTransparency)
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
                    Button { withAnimation(.snappy) { settings.model = model } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: settings.model == model ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(settings.model == model ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(model.title).font(.callout.weight(.medium))
                                Text(model.help).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(settings.model == model ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
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
                QualityRow(title: "Qualidade", value: Binding(get: { 100 - settings.compression }, set: { settings.compression = 100 - $0 }),
                           range: 1...100)
            }
            Label("Usa a GPU do Mac. Imagens grandes podem levar alguns segundos.", systemImage: "cpu")
                .font(.caption).foregroundStyle(.secondary)
        }
        UpscaleCredits()
    }
}

private struct UpscaleCredits: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Motor de IA: Upscayl (AGPL-3.0) · Real-ESRGAN")
            Link("Código-fonte", destination: URL(string: "https://github.com/upscayl/upscayl-ncnn")!)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .padding(.leading, 2)
    }
}

// MARK: - Save

private struct SaveSection: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings
    let open: (SheetRoute) -> Void
    @State private var showAdvanced = false

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
            }
            Toggle("Não substituir arquivos existentes", isOn: $settings.skipExisting)
            DisclosureGroup("Opções avançadas", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    if settings.mode != .upscale {
                        Toggle("Usar opções avançadas", isOn: $settings.useAdvancedOptions)
                        Button("Configurar Opções Avançadas…") { open(.advanced) }
                        if settings.useAdvancedOptions { ActiveStepsSummary(options: settings.advanced) }
                        Divider()
                    }
                    Toggle("Extensão em MAIÚSCULAS", isOn: $settings.uppercaseExtension)
                    Toggle("Manter data e hora originais", isOn: $settings.keepDates)
                    Toggle("Perguntar antes de sobrescrever", isOn: $settings.askBeforeOverwrite)
                        .disabled(settings.skipExisting)
                    Toggle("Mostrar mensagens de erro", isOn: $settings.showErrors)
                    if settings.mode != .upscale {
                        Toggle("Processar várias imagens ao mesmo tempo", isOn: $settings.parallel)
                    }
                    Toggle("Abrir pasta ao concluir", isOn: $settings.openFolderWhenDone)
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
            Button("Escolher…") {
                if let url = FilePanels.chooseFolder(startingAt: path) { path = url.path }
            }
            Button("Mostrar", systemImage: "arrow.right.circle") {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
            .labelStyle(.iconOnly)
            .disabled(path.isEmpty)
        }
    }
}

/// Small capsules naming the enabled Advanced Options steps.
struct ActiveStepsSummary: View {
    let options: AdvancedOptions

    var body: some View {
        let steps = AdvancedStep.allCases.filter { $0.isEnabled(in: options) }
        if steps.isEmpty {
            Text("Nenhuma etapa ativada").font(.caption).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(steps) { step in
                    Label(step.title, systemImage: step.symbol)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: .capsule)
                }
            }
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
