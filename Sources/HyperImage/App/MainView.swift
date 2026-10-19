import HyperImageCore
import SwiftUI

enum SheetRoute: Identifiable {
    case formatSettings, advanced, progress, conversionPreview(URL)

    var id: String {
        switch self {
        case .formatSettings: "format"
        case .advanced: "advanced"
        case .progress: "progress"
        case let .conversionPreview(url): "preview-\(url.path)"
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var browser: BrowserModel?
    @State private var sheet: SheetRoute?
    @State private var showInspector = true
    @State private var runner = ConversionRunner()

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            if let browser {
                BrowserView(browser: browser)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
            }
        } detail: {
            // A plain trailing column instead of `.inspector`: on windows narrower than ~1360 pt the system
            // inspector and the toolbar kept re-laying each other out until AppKit aborted the launch
            // ("more Update Constraints in Window passes than there are views").
            HStack(spacing: 0) {
                InputListView(preview: { sheet = .conversionPreview($0) })
                    .frame(minWidth: 420)
                if showInspector {
                    Divider()
                    inspector
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy(duration: 0.25), value: showInspector)
        }
        .navigationTitle("HyperImage Converter")
        .toolbar { toolbar }
        .sheet(item: $sheet) { route in sheetView(route) }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .onAppear {
            if browser == nil {
                let model = BrowserModel(path: app.state.browserPath, filterName: app.state.filterName)
                model.reload()
                browser = model
            }
            #if DEBUG
            if let route = DebugLaunch.apply(to: app) { sheet = route }
            if DebugLaunch.env["HYPERIMAGE_SHEET"] == "progress", !app.inputs.isEmpty { startConversion() }
            if DebugLaunch.env["HYPERIMAGE_WINDOW"] == "about" { openWindow(id: "about") }
            #endif
        }
    }

    @ViewBuilder
    private var inspector: some View {
        ConvertInspector(open: { sheet = $0 })
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Adicionar", systemImage: "plus") { FilePanels.addFiles(to: app) }
                .help("Adicionar arquivos ou pastas (⌘O)")
            Button("Remover", systemImage: "minus") { app.removeSelected() }
                .disabled(app.selection.isEmpty)
                .help("Remover os selecionados da lista")
            Button("Limpar", systemImage: "trash") { app.clear() }
                .disabled(app.inputs.isEmpty)
                .help("Remover todos da lista")
        }
        ToolbarItemGroup {
            Button("Pré-visualizar", systemImage: "eye") {
                if let url = app.selectedItem?.url ?? app.inputs.first?.url { sheet = .conversionPreview(url) }
            }
            .disabled(app.inputs.isEmpty)
            .help("Comparar antes e depois")
            Button("Converter", systemImage: "play.fill") { startConversion() }
                .buttonStyle(.borderedProminent)
                .disabled(app.inputs.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            inspectorToggle
        }
    }

    private var inspectorToggle: some View {
        Button("Inspetor", systemImage: "sidebar.right") { showInspector.toggle() }
            .help(showInspector ? "Ocultar inspetor" : "Mostrar inspetor")
    }

    @ViewBuilder
    private func sheetView(_ route: SheetRoute) -> some View {
        switch route {
        case .formatSettings: FormatSettingsSheet()
        case .advanced: AdvancedOptionsSheet()
        case .progress: ConversionProgressSheet(runner: runner)
        case let .conversionPreview(url): ConversionPreviewSheet(initial: url)
        }
    }

    private func startConversion() {
        let settings = app.state.convert
        if settings.useAdvancedOptions, let message = settings.advanced.validationError() {
            app.alert = AppAlert(title: String(localized: "Opções avançadas"), message: message)
            return
        }
        if settings.useOutputFolder && settings.outputFolder.isEmpty {
            guard let folder = FilePanels.chooseFolder(prompt: String(localized: "Usar como Saída")) else { return }
            app.state.convert.outputFolder = folder.path
        }
        runner.start(items: app.inputs, settings: app.state.convert)
        sheet = .progress
    }
}
