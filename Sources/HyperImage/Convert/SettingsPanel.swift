import HyperImageCore
import SwiftUI

/// Right side of the window: a native grouped form with the options; the summary floats over it in glass.
struct SettingsPanel: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let start: () -> Void
    @State private var estimator = EstimateStore()

    var body: some View {
        @Bindable var app = app
        let settings = $app.state.convert
        Form {
            switch app.state.convert.mode {
            case .convert:
                selectedPreview
                ConvertSections(settings: settings)
            case .compress:
                CompressSections(settings: settings, estimate: estimator.estimate, hasInputs: !app.inputs.isEmpty)
                selectedPreview
                SaveSection(settings: settings)
            case .upscale:
                selectedPreview
                UpscaleSections(settings: settings.upscale)
                SaveSection(settings: settings)
            }
        }
        .formStyle(.grouped)
        // The panel runs up under the toolbar (like Finder's inspector), so its background fills the whole column;
        // no toolbar items sit above it, so the first section starts at the top.
        .contentMargins(.top, 6, for: .scrollContent)
        .scrollEdgeEffectHidden(true, for: .top)
        .ignoresSafeArea(.container, edges: .top)
        .toggleStyle(.switch)
        .animation(.snappy, value: app.state.convert.mode)
        .animation(.snappy, value: app.state.showPreview)
        .animation(.snappy, value: app.selectedItem?.url)
        .disabled(runner.isRunning)
        .scrollEdgeEffectHidden(true, for: .bottom)
        // Floating, so the form scrolls underneath instead of being covered.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Comprimir shows its estimate up top, so its summary keeps only the action and the result.
            SummaryBox(runner: runner, start: start, estimate: estimator.estimate,
                       showsEstimate: app.state.convert.mode != .compress)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 4)
        }
        .frame(width: 360)
        .task(id: EstimateKey(app.state.convert, revision: app.inputsRevision)) {
            await estimator.refresh(urls: app.inputs.map(\.url), settings: app.state.convert)
        }
    }

    @ViewBuilder
    private var selectedPreview: some View {
        if app.state.showPreview, let item = app.selectedItem { PreviewSection(item: item) }
    }
}

// MARK: - Building blocks

/// Switch with an optional one-line explanation underneath its title.
struct ToggleRow: View {
    let title: LocalizedStringKey
    var help: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help { Text(help).font(.callout).foregroundStyle(.secondary) }
            }
        }
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
                Text(title)
                Spacer()
                Text("\(value) %").foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy, value: value)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: range)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text("\(value) %"))
            HStack {
                Text("Menor arquivo")
                Spacer()
                Text("Mais qualidade")
            }
            .font(.caption).foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
    }
}

/// Number field + stepper + common presets, applied as the user types.
struct NumberRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let presets: [(String, Int)]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number.grouping(.never))
                    .labelsHidden()
                    .frame(width: 70).multilineTextAlignment(.trailing)
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
}

// MARK: - AI Upscale

struct UpscaleSections: View {
    @Binding var settings: UpscaleSettings

    var body: some View {
        Section("Modelo de IA") {
            ForEach(UpscaleModel.allCases, id: \.self) { model in
                let selected = settings.model == model
                Button { withAnimation(.snappy) { settings.model = model } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.title)
                            Text(model.help).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        Section {
            Picker("Escala", selection: $settings.scale) {
                Text("2×").tag(2)
                Text("3×").tag(3)
                Text("4×").tag(4)
            }
            .pickerStyle(.segmented)
            Picker("Formato", selection: $settings.format.animation(.snappy)) {
                Text("PNG").tag(UpscaleFormat.png)
                Text("JPEG").tag(UpscaleFormat.jpeg)
                Text("WebP").tag(UpscaleFormat.webp)
            }
            .pickerStyle(.segmented)
            if settings.format != .png {
                QualityRow(title: "Qualidade", value: Binding(get: { 100 - settings.compression }, set: { settings.compression = 100 - $0 }))
                    .transition(.blurReplace)
            }
        } header: {
            Text("Ampliação")
        } footer: {
            Text("Usa a GPU do Mac; o tempo restante aparece depois do início. Motor: Upscayl (AGPL-3.0) com Real-ESRGAN — [código-fonte](https://github.com/upscayl/upscayl-ncnn).")
        }
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

struct SaveSection: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings
    @State private var showMore = false

    var body: some View {
        Section("Salvar") {
            Picker("Destino", selection: $settings.useOutputFolder.animation(.snappy)) {
                Text("Ao lado dos originais").tag(false)
                Text("Em uma pasta").tag(true)
            }
            if settings.useOutputFolder {
                OutputFolderRow(path: $settings.outputFolder).transition(.blurReplace)
                if app.hasFolderItems {
                    Toggle("Manter estrutura de pastas", isOn: $settings.keepFolderStructure).transition(.blurReplace)
                }
            }
            if settings.mode != .upscale {
                Toggle("Adicionar sufixo (\(settings.mode == .compress ? "-comprimido" : "-convertido"))", isOn: $settings.addSuffix)
                    .disabled(settings.rename && settings.mode == .convert)
            }
            // Naming templates belong to converting; Comprimir keeps names simple.
            if settings.mode == .convert {
                OutputRenameRows(settings: $settings)
            }
            Picker("Se o arquivo já existir", selection: Binding(get: { ExistingFilePolicy(settings) }, set: { $0.apply(to: &settings) })) {
                Text("Perguntar").tag(ExistingFilePolicy.ask)
                Text("Pular").tag(ExistingFilePolicy.skip)
                Text("Substituir").tag(ExistingFilePolicy.replace)
            }
        }
        Section {
            DisclosureGroup("Mais opções", isExpanded: $showMore.animation(.snappy)) {
                Toggle("Extensão em maiúsculas (.JPG)", isOn: $settings.uppercaseExtension)
                Toggle("Manter data e hora originais", isOn: $settings.keepDates)
                Toggle("Abrir a lista de erros ao terminar", isOn: $settings.showErrors)
                if settings.mode != .upscale {
                    Toggle("Processar várias imagens ao mesmo tempo", isOn: $settings.parallel)
                }
                Toggle("Abrir a pasta ao concluir", isOn: $settings.openFolderWhenDone)
            }
        }
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

/// Folder icon and name (full path in the tooltip and the menu), with Change and Show in Finder.
private struct OutputFolderRow: View {
    @Binding var path: String

    private var url: URL? { path.isEmpty ? nil : URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

    var body: some View {
        LabeledContent("Pasta") {
            HStack(spacing: 8) {
                if let url {
                    Menu {
                        Text(url.path)
                        Divider()
                        Button("Mostrar no Finder") {
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Button("Alterar…") { choose() }
                    } label: {
                        Label {
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 18, height: 18)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(url.path)
                } else {
                    Button("Escolher…") { choose() }
                }
            }
        }
    }

    private func choose() {
        if let chosen = FilePanels.chooseFolder(startingAt: path) { path = chosen.path }
    }
}
