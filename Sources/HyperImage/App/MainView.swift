import HyperImageCore
import SwiftUI

enum SheetRoute: Identifiable {
    case formatSettings, advanced, progress, renamePreview, conversionPreview(URL)

    var id: String {
        switch self {
        case .formatSettings: "format"
        case .advanced: "advanced"
        case .progress: "progress"
        case .renamePreview: "renamePreview"
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
            InputListView(preview: { sheet = .conversionPreview($0) })
                .inspector(isPresented: $showInspector) {
                    inspector
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
                }
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
        switch app.state.mode {
        case .convert: ConvertInspector(open: { sheet = $0 })
        case .rename: RenameInspector(open: { sheet = $0 })
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Modo", selection: Binding(get: { app.state.mode }, set: { app.state.mode = $0 })) {
                Label("Converter", systemImage: "arrow.triangle.2.circlepath").tag(AppMode.convert)
                Label("Renomear", systemImage: "character.cursor.ibeam").tag(AppMode.rename)
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
        }
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
            if app.state.mode == .convert {
                Button("Pré-visualizar", systemImage: "eye") {
                    if let url = app.selectedItem?.url ?? app.inputs.first?.url { sheet = .conversionPreview(url) }
                }
                .disabled(app.inputs.isEmpty)
                .help("Comparar antes e depois")
                Button("Converter", systemImage: "play.fill") { startConversion() }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.inputs.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Pré-visualizar", systemImage: "eye") { sheet = .renamePreview }
                    .disabled(app.inputs.isEmpty)
                Button("Renomear", systemImage: "play.fill") { sheet = .renamePreview }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.inputs.isEmpty)
            }
            Button("Inspetor", systemImage: "sidebar.right") { showInspector.toggle() }
        }
    }

    @ViewBuilder
    private func sheetView(_ route: SheetRoute) -> some View {
        switch route {
        case .formatSettings: FormatSettingsSheet()
        case .advanced: AdvancedOptionsSheet()
        case .progress: ConversionProgressSheet(runner: runner)
        case .renamePreview: RenamePreviewSheet()
        case let .conversionPreview(url): ConversionPreviewSheet(initial: url)
        }
    }

    private func startConversion() {
        let settings = app.state.convert
        if settings.useAdvancedOptions, let message = settings.advanced.validationError() {
            app.alert = AppAlert(title: "Opções avançadas", message: message)
            return
        }
        if settings.useOutputFolder && settings.outputFolder.isEmpty {
            guard let folder = FilePanels.chooseFolder(prompt: "Usar como Saída") else { return }
            app.state.convert.outputFolder = folder.path
        }
        runner.start(items: app.inputs, settings: app.state.convert)
        sheet = .progress
    }
}
