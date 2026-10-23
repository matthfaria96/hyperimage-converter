import HyperImageCore
import SwiftUI

enum SheetRoute: Identifiable {
    case formatSettings, advanced(AdvancedStep?), conversionPreview(URL), errors

    var id: String {
        switch self {
        case .formatSettings: "format"
        case let .advanced(step): step.map { "advanced-\($0.rawValue)" } ?? "advanced"
        case let .conversionPreview(url): "preview-\(url.path)"
        case .errors: "errors"
        }
    }
}

/// Window layout: the file list and, always beside it, the options panel. Mode switch and list actions live in the toolbar.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var runner = ConversionRunner()

    private var canPreview: Bool { app.state.convert.mode != .upscale && !runner.isRunning }

    var body: some View {
        @Bindable var app = app
        // Plain columns instead of NavigationSplitView/.inspector: a collapsed split-view sidebar leaves an empty
        // "»" overflow button in the macOS 26 toolbar, and the system inspector re-laid the toolbar out until
        // AppKit aborted the launch on narrow windows.
        // Plain columns instead of NavigationSplitView/.inspector: those leave an empty "»" overflow button in the
        // macOS 26 toolbar, and the system inspector re-laid the toolbar out until AppKit aborted on narrow windows.
        HStack(spacing: 0) {
            WorkspaceView(runner: runner, canPreview: canPreview)
                .frame(minWidth: 460)
            Divider().ignoresSafeArea()
            SettingsPanel(runner: runner, start: startConversion)
        }
        .navigationTitle(Text(app.state.convert.mode.title))
        .toolbar(removing: .title)
        // No toolbar backdrop: both columns run up under the floating glass controls, so nothing leaves a band on top.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { toolbarContent }
        .sheet(item: $app.route) { route in sheetView(route) }
        .overlay {
            if let prompt = runner.prompt { OverwritePanel(url: prompt.url, answer: runner.answer) }
        }
        .animation(.snappy, value: runner.prompt?.url)
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .onChange(of: runner.completionID) { batchFinished() }
        .onChange(of: runner.isRunning) { _, running in app.isBusy = running }
        .onChange(of: runner.progress) { _, value in DockProgress.show(runner.isRunning ? value : nil) }
        .onChange(of: app.startRequest) { startConversion() }
        .onChange(of: runner.openFolderWhenDone) { _, value in app.state.convert.openFolderWhenDone = value }
        .onAppear {
            // AppKit focuses the first text field at launch; start with nothing focused.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            #if DEBUG
            if let route = DebugLaunch.apply(to: app) { app.route = route }
            if DebugLaunch.env["HYPERIMAGE_SHEET"] == "progress", !app.inputs.isEmpty { startConversion() }
            if DebugLaunch.env["HYPERIMAGE_WINDOW"] == "about" { openWindow(id: "about") }
            #endif
        }
    }

    // MARK: Toolbar

    /// Separate items, not a group: grouped menus made the toolbar overflow into "»" on macOS 26.
    /// The mode picker leads the toolbar (Finder style); the title is left out, since it collided with the picker.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var app = app
        ToolbarItem(placement: .navigation) {
            Picker("Modo", selection: $app.state.convert.mode.animation(.snappy)) {
                ForEach(ConvertMode.allCases, id: \.self) { mode in
                    Text(mode.tabTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(runner.isRunning)
            .help("⌘1 Converter · ⌘2 Comprimir · ⌘3 AI Upscale")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Adicionar imagens…", systemImage: "plus") { FilePanels.addFiles(to: app) }
                .disabled(runner.isRunning)
                .help("Adicionar imagens ou pastas (⌘O)")
        }
        ToolbarItem(placement: .primaryAction) { SortMenu() }
        ToolbarItem(placement: .primaryAction) { ListActionsMenu(runner: runner, canPreview: canPreview) }
    }

    // MARK: Sheets and actions

    @ViewBuilder
    private func sheetView(_ route: SheetRoute) -> some View {
        switch route {
        case .formatSettings: FormatSettingsSheet()
        case let .advanced(step): AdvancedOptionsSheet(initialStep: step)
        case let .conversionPreview(url): ConversionPreviewSheet(initial: url)
        case .errors: ErrorListSheet(failures: runner.failures)
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
            guard let folder = FilePanels.chooseFolder(prompt: String(localized: "Usar como saída")) else { return }
            app.state.convert.outputFolder = folder.path
        }
        runner.start(items: app.inputs, settings: app.state.convert)
    }

    /// Errors are listed in the rows and in "Ver erros"; an alert only interrupts for a batch-wide failure.
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

/// "…" toolbar menu with the actions that apply to the list or the selection.
private struct ListActionsMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    let runner: ConversionRunner
    let canPreview: Bool

    var body: some View {
        Menu {
            Button("Pré-visualizar", systemImage: "eye") {
                if let url = app.previewTarget { app.route = .conversionPreview(url) }
            }
            .disabled(!canPreview || app.inputs.isEmpty)
            Button("Selecionar tudo") { app.selectAll() }
                .disabled(app.inputs.isEmpty)
            Toggle("Mostrar pré-visualização", isOn: Binding(get: { app.state.showPreview }, set: { app.state.showPreview = $0 }))
            Divider()
            Button("Mostrar no Finder") { FilePanels.reveal(Array(app.selection)) }
                .disabled(app.selection.isEmpty)
            Button("Remover da lista") { ListEdits.remove(app.selection, from: app, undo: undoManager, running: runner.isRunning) }
                .disabled(app.selection.isEmpty || runner.isRunning)
            Divider()
            Button("Limpar lista", role: .destructive) {
                ListEdits.remove(Set(app.inputs.map(\.url)), from: app, undo: undoManager, running: runner.isRunning)
            }
            .disabled(app.inputs.isEmpty || runner.isRunning)
        } label: {
            Label("Mais ações", systemImage: "ellipsis.circle")
        }
        .help("Mais ações para a lista")
    }
}
