import HyperImageCore
import SwiftUI

enum SheetRoute: Identifiable {
    case formatSettings, advanced, conversionPreview(URL)

    var id: String {
        switch self {
        case .formatSettings: "format"
        case .advanced: "advanced"
        case let .conversionPreview(url): "preview-\(url.path)"
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var browser: BrowserModel?
    @State private var sheet: SheetRoute?
    @State private var runner = ConversionRunner()
    /// The file browser is optional in the simplified layout: hidden until the sidebar button shows it.
    @State private var columns = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columns) {
            if let browser {
                BrowserView(browser: browser)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 480)
            }
        } detail: {
            // A plain trailing column instead of `.inspector`: on narrow windows the system inspector and the
            // toolbar kept re-laying each other out until AppKit aborted the launch.
            HStack(spacing: 0) {
                WorkspaceView(runner: runner, preview: { sheet = .conversionPreview($0) })
                    .frame(minWidth: 460)
                Divider()
                SettingsPanel(runner: runner, open: { sheet = $0 }, start: startConversion)
            }
        }
        .navigationTitle("HyperImage Converter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Abrir pasta de saída", systemImage: "folder") { openOutputFolder() }
                    .help("Abrir no Finder a pasta onde os arquivos são salvos")
                    .disabled(app.state.convert.useOutputFolder && app.state.convert.outputFolder.isEmpty
                              || !app.state.convert.useOutputFolder && app.inputs.isEmpty)
            }
        }
        .sheet(item: $sheet) { route in sheetView(route) }
        .overlay {
            if let prompt = runner.prompt { OverwritePanel(url: prompt.url, answer: runner.answer) }
        }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .onChange(of: runner.completionID) { reportFailures() }
        .onChange(of: runner.openFolderWhenDone) { _, value in app.state.convert.openFolderWhenDone = value }
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
    private func sheetView(_ route: SheetRoute) -> some View {
        switch route {
        case .formatSettings: FormatSettingsSheet()
        case .advanced: AdvancedOptionsSheet()
        case let .conversionPreview(url): ConversionPreviewSheet(initial: url)
        }
    }

    private func startConversion() {
        guard !runner.isRunning, !app.inputs.isEmpty else { return }
        let settings = app.state.convert
        if settings.mode != .upscale, settings.useAdvancedOptions, let message = settings.advanced.validationError() {
            app.alert = AppAlert(title: String(localized: "Opções avançadas"), message: message)
            return
        }
        if settings.useOutputFolder && settings.outputFolder.isEmpty {
            guard let folder = FilePanels.chooseFolder(prompt: String(localized: "Usar como Saída")) else { return }
            app.state.convert.outputFolder = folder.path
        }
        runner.start(items: app.inputs, settings: app.state.convert)
    }

    private func openOutputFolder() {
        let settings = app.state.convert
        if let folder = settings.outputFolderURL {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } else if let first = app.inputs.first {
            NSWorkspace.shared.open(first.url.deletingLastPathComponent())
        }
    }

    private func reportFailures() {
        guard !runner.isRunning else { return }
        if let failure = runner.failure {
            app.alert = AppAlert(title: String(localized: "Falha na conversão"), message: failure)
        } else if runner.settings.showErrors, !runner.failures.isEmpty, !runner.wasCancelled {
            app.alert = AppAlert(title: String(localized: "\(runner.failures.count) arquivo(s) com erro"),
                                 message: runner.failures.prefix(8).map { r in
                                     "\(r.input.lastPathComponent): \(errorText(r.status))"
                                 }.joined(separator: "\n"))
        }
    }
}
