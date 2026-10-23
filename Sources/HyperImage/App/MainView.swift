import HyperImageCore
import SwiftUI

enum SheetRoute: Identifiable {
    case formatSettings, advanced(AdvancedStep?), conversionPreview(URL), errors, renamePreview

    var id: String {
        switch self {
        case .formatSettings: "format"
        case let .advanced(step): step.map { "advanced-\($0.rawValue)" } ?? "advanced"
        case let .conversionPreview(url): "preview-\(url.path)"
        case .errors: "errors"
        case .renamePreview: "renamePreview"
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var browser: BrowserModel?
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
                WorkspaceView(runner: runner, browserVisible: columns != .detailOnly,
                              toggleBrowser: { withAnimation { columns = columns == .detailOnly ? .all : .detailOnly } })
                    .frame(minWidth: 460)
                Divider()
                SettingsPanel(runner: runner, start: startConversion)
            }
        }
        .navigationTitle("HyperImage Converter")
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Navegador de pastas", systemImage: "sidebar.leading") {
                    withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
                }
                .help("Mostrar ou ocultar o navegador de pastas (⌃⌘S)")
            }
        }
        .sheet(item: $app.route) { route in sheetView(route) }
        .overlay {
            if let prompt = runner.prompt { OverwritePanel(url: prompt.url, answer: runner.answer) }
        }
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .onChange(of: runner.completionID) { batchFinished() }
        .onChange(of: runner.isRunning) { _, running in app.isBusy = running }
        .onChange(of: runner.progress) { _, value in DockProgress.show(runner.isRunning ? value : nil) }
        .onChange(of: app.startRequest) { startConversion() }
        .onChange(of: runner.openFolderWhenDone) { _, value in app.state.convert.openFolderWhenDone = value }
        .onAppear {
            if browser == nil {
                let model = BrowserModel(path: app.state.browserPath, filterName: app.state.filterName)
                model.reload()
                browser = model
            }
            #if DEBUG
            if let route = DebugLaunch.apply(to: app) { app.route = route }
            if DebugLaunch.env["HYPERIMAGE_SHEET"] == "progress", !app.inputs.isEmpty { startConversion() }
            if DebugLaunch.env["HYPERIMAGE_WINDOW"] == "about" { openWindow(id: "about") }
            #endif
        }
    }

    @ViewBuilder
    private func sheetView(_ route: SheetRoute) -> some View {
        switch route {
        case .formatSettings: FormatSettingsSheet()
        case let .advanced(step): AdvancedOptionsSheet(initialStep: step)
        case let .conversionPreview(url): ConversionPreviewSheet(initial: url)
        case .errors: ErrorListSheet(failures: runner.failures)
        case .renamePreview: RenamePreviewSheet()
        }
    }

    private func startConversion() {
        guard !runner.isRunning, !app.inputs.isEmpty else { return }
        if app.state.convert.mode == .rename { app.route = .renamePreview; return }
        let settings = app.state.convert
        if settings.mode != .upscale, settings.useAdvancedOptions, let message = settings.advanced.validationError() {
            app.alert = AppAlert(title: String(localized: "Opções avançadas"), message: message)
            return
        }
        if settings.useOutputFolder && settings.outputFolder.isEmpty {
            guard let folder = FilePanels.chooseFolder(prompt: String(localized: "Usar como saída")) else { return }
            app.state.convert.outputFolder = folder.path
        }
        runner.start(items: app.inputs, settings: app.state.convert)
    }

    /// Errors are listed in the cards and in "Ver erros"; an alert only interrupts for a batch-wide failure.
    private func batchFinished() {
        guard !runner.isRunning else { return }
        DockProgress.show(nil)
        if let failure = runner.failure {
            app.alert = AppAlert(title: String(localized: "Falha na conversão"), message: failure)
        } else if runner.settings.showErrors, !runner.failures.isEmpty, !runner.wasCancelled {
            app.route = .errors
        }
        guard runner.hasResults, !runner.wasCancelled else { return }
        CompletionNotifier.notify(done: runner.doneCount, failed: runner.failures.count,
                                  saved: runner.oldTotal - runner.newTotal, mode: runner.settings.mode)
    }
}
