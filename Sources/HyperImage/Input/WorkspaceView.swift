import AppKit
import HyperImageCore
import SwiftUI

/// Centre of the window: the drop bar, the queued files as a native list and a status footer.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    let runner: ConversionRunner
    let canPreview: Bool
    @State private var dropTargeted = false
    /// The file list takes focus at launch, so AppKit does not pick (and scroll to) a text field in the options panel.
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            Group {
                if app.inputs.isEmpty {
                    EmptyDropZone(targeted: dropTargeted, addFiles: { FilePanels.addFiles(to: app) })
                        .focusable()
                        .focusEffectDisabled()
                        .focused($listFocused)
                        .transition(.blurReplace)
                } else {
                    fileList
                        .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy, value: app.inputs.isEmpty)
            Divider()
            statusBar
        }
        .background(.background)
        .dropDestination(for: URL.self) { urls, _ in
            // The list is frozen while a batch runs, so results always match what is shown.
            guard !runner.isRunning else { return false }
            return withAnimation(.snappy) { app.addInBackground(urls); return true }
        } isTargeted: { dropTargeted = $0 && !runner.isRunning }
        .overlay {
            if dropTargeted && !app.inputs.isEmpty { DropOverlay() }
        }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .onDeleteCommand { remove(app.selection) }
        .onAppear { listFocused = true }
        .defaultFocus($listFocused, true)
        #if DEBUG
        .onAppear { if DebugLaunch.env["HYPERIMAGE_DROP"] != nil { dropTargeted = true } }
        #endif
    }

    // MARK: Files

    private var fileList: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            CompactDropZone(targeted: dropTargeted) { FilePanels.addFiles(to: app) }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            List(selection: $app.selection) {
                ForEach(app.inputs) { item in
                    FileRow(item: item, record: runner.record(for: item.url), isRunning: runner.isRunning,
                            showsRatio: app.state.convert.mode == .convert || app.state.convert.mode == .compress,
                            canPreview: canPreview,
                            working: runner.currentUpscale == item.url ? runner.partial : nil,
                            estimateSettings: app.state.convert.mode == .compress && !runner.isRunning ? app.state.convert : nil,
                            preview: { app.route = .conversionPreview(item.url) },
                            remove: { remove([item.url]) })
                        .tag(item.url)
                }
            }
            .listStyle(.inset)
            .focused($listFocused)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .animation(.snappy, value: app.inputsRevision)
            .contextMenu(forSelectionType: URL.self) { urls in
                contextMenu(for: urls)
            } primaryAction: { urls in
                guard canPreview, let url = urls.first else { return }
                app.route = .conversionPreview(url)
            }
            .onKeyPress(.space) {
                guard canPreview, let url = app.previewTarget else { return .ignored }
                app.route = .conversionPreview(url)
                return .handled
            }
        }
    }

    // MARK: Actions

    private func remove(_ urls: Set<URL>) {
        ListEdits.remove(urls, from: app, undo: undoManager, running: runner.isRunning)
    }

    @ViewBuilder
    private func contextMenu(for urls: Set<URL>) -> some View {
        if urls.isEmpty {
            Button("Adicionar imagens…") { FilePanels.addFiles(to: app) }
        } else {
            Button("Pré-visualizar") { if let url = urls.first { app.route = .conversionPreview(url) } }
                .disabled(!canPreview)
            Button("Mostrar no Finder") { FilePanels.reveal(Array(urls)) }
            let done = urls.compactMap { runner.record(for: $0) }.filter { $0.status == .done }
            if !done.isEmpty {
                Button("Mostrar resultado no Finder") { FilePanels.reveal(done.map(\.output)) }
            }
            Divider()
            Button("Remover", role: .destructive) { remove(urls) }
                .disabled(runner.isRunning)
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Text(countText(app.inputs.count))
            if app.totalBytes > 0 { Text("·"); Text("\(formatBytes(app.totalBytes)) no total") }
            if !app.selection.isEmpty { Text("·"); Text("\(app.selection.count) selecionada(s)") }
            if app.isScanning {
                ProgressView().controlSize(.mini)
                Text("Lendo imagens…")
            }
            Spacer()
            Button { app.route = .history } label: {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
                    .symbolEffect(.bounce, value: app.history.entries.count)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Imagens convertidas antes (⌘⇧H)")
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.snappy, value: app.inputs.count)
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    private func countText(_ n: Int) -> String {
        switch n {
        case 0: String(localized: "Nenhuma imagem")
        case 1: String(localized: "1 imagem")
        default: String(localized: "\(n) imagens")
        }
    }
}

/// List edits shared by the toolbar menu, the context menu and ⌫, all undoable.
enum ListEdits {
    static func remove(_ urls: Set<URL>, from app: AppModel, undo: UndoManager?, running: Bool) {
        guard !urls.isEmpty, !running else { return }
        let before = app.inputs
        let selection = app.selection
        undo?.registerUndo(withTarget: app) { model in
            model.restore(before)
            model.selection = selection
        }
        undo?.setActionName(urls.count == before.count ? String(localized: "Limpar lista") : String(localized: "Remover imagens"))
        withAnimation(.snappy) { app.remove(urls) }
    }
}

extension ConvertMode {
    var tabTitle: LocalizedStringKey {
        switch self {
        case .convert: "Converter"
        case .compress: "Comprimir"
        case .upscale: "AI Upscale"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .upscale: "sparkles"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .convert: "Converter imagens"
        case .compress: "Comprimir imagens"
        case .upscale: "AI Upscale"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .convert: "Converta formatos ou reduza o tamanho em poucos cliques."
        case .compress: "Comprima arquivos mantendo o formato e a melhor qualidade possível."
        case .upscale: "Aumente a resolução em até 4× recriando detalhes com IA, direto no seu Mac."
        }
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .convert: "Converter imagens"
        case .compress: "Comprimir imagens"
        case .upscale: "Ampliar imagens"
        }
    }
}

struct SortMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Picker("Ordenar por", selection: Binding(get: { app.state.sort.key }, set: { app.setSort(InputSort(key: $0, descending: app.state.sort.descending)) })) {
                Text("Ordem de adição").tag(InputSortKey.none)
                Text("Nome").tag(InputSortKey.name)
                Text("Tamanho").tag(InputSortKey.size)
                Text("Data da foto").tag(InputSortKey.dateTaken)
                Text("Tipo").tag(InputSortKey.type)
            }
            .pickerStyle(.inline)
            Toggle("Ordem decrescente", isOn: Binding(get: { app.state.sort.descending }, set: { app.setSort(InputSort(key: app.state.sort.key, descending: $0)) }))
                .disabled(app.state.sort.key == .none)
        } label: {
            Label("Ordenar por: \(sortTitle)", systemImage: "arrow.up.arrow.down")
        }
    }

    private var sortTitle: String {
        let name = switch app.state.sort.key {
        case .none: String(localized: "Ordem de adição")
        case .name: String(localized: "Nome")
        case .size: String(localized: "Tamanho")
        case .dateTaken: String(localized: "Data da foto")
        case .type: String(localized: "Tipo")
        }
        return app.state.sort.descending && app.state.sort.key != .none ? "\(name) ↓" : name
    }
}
