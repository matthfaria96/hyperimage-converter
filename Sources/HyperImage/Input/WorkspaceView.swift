import AppKit
import HyperImageCore
import SwiftUI

/// Left side of the window: mode tabs, drop area and the queued files as cards.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    let runner: ConversionRunner
    let browserVisible: Bool
    let toggleBrowser: () -> Void
    @State private var dropTargeted = false
    @State private var folderTargets: Set<URL> = []
    @State private var folderName = ""
    @State private var askingFolderName = false
    /// Anchor for ⇧-click range selection.
    @State private var anchor: URL?
    @FocusState private var listFocused: Bool

    private var canPreview: Bool { ![.upscale, .rename].contains(app.state.convert.mode) && !runner.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if app.inputs.isEmpty {
                    EmptyDropZone(targeted: dropTargeted, addFiles: { FilePanels.addFiles(to: app) }, browse: { if !browserVisible { toggleBrowser() } })
                } else {
                    fileList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .background(.background)
        .dropDestination(for: URL.self) { urls, _ in
            // The list is frozen while a batch runs, so results always match what is shown.
            guard !runner.isRunning else { return false }
            return withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { app.addInBackground(urls); return true }
        } isTargeted: { dropTargeted = $0 && !runner.isRunning }
        .overlay {
            if dropTargeted && !app.inputs.isEmpty { DropOverlay() }
        }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .onDeleteCommand { removeWithUndo(app.selection) }
        .alert("Agrupar em subpasta de saída", isPresented: $askingFolderName) {
            TextField("Nome da subpasta", text: $folderName)
            Button("Cancelar", role: .cancel) {}
            Button("Agrupar") { app.move(folderTargets, toFolder: InputItem.folderName(folderName)) }
                .disabled(InputItem.folderName(folderName) == nil)
        } message: {
            Text("As imagens escolhidas serão salvas dentro de uma subpasta com este nome, no destino que você definir. Nada é criado agora.")
        }
        #if DEBUG
        .onAppear { if DebugLaunch.env["HYPERIMAGE_DROP"] != nil { dropTargeted = true } }
        #endif
    }

    // MARK: Header

    private var header: some View {
        @Bindable var app = app
        let picker = Picker("Modo", selection: $app.state.convert.mode.animation(.snappy)) {
            ForEach(ConvertMode.allCases, id: \.self) { mode in
                Label(mode.tabTitle, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(runner.isRunning)
        .help("⌘1 Converter · ⌘2 Comprimir · ⌘3 AI Upscale · ⌘4 Renomear")

        let titleBlock = VStack(alignment: .leading, spacing: 2) {
            Text(app.state.convert.mode.title).font(.title2.weight(.bold))
            Text(app.state.convert.mode.subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleBlock
                Spacer(minLength: 12)
                picker
            }
            VStack(alignment: .leading, spacing: 10) {
                titleBlock
                picker
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    // MARK: Files

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CompactDropZone(targeted: dropTargeted) { FilePanels.addFiles(to: app) }
                listHeader
                LazyVStack(spacing: 7) {
                    ForEach(app.inputs) { item in
                        FileCard(item: item, record: runner.record(for: item.url), isRunning: runner.isRunning,
                                 isSelected: app.selection.contains(item.url),
                                 showsRatio: app.state.convert.mode == .convert || app.state.convert.mode == .compress,
                                 canPreview: canPreview,
                                 working: runner.currentUpscale == item.url ? runner.partial : nil,
                                 preview: { app.route = .conversionPreview(item.url) }) {
                            removeWithUndo([item.url])
                        }
                        .onTapGesture { select(item.url) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if canPreview { app.route = .conversionPreview(item.url) }
                        })
                        .contextMenu { contextMenu(for: item.url) }
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity.combined(with: .scale(scale: 0.96))))
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard canPreview, let url = app.previewTarget else { return .ignored }
            app.route = .conversionPreview(url)
            return .handled
        }
        .onKeyPress(characters: ["a"], phases: .down) { press in
            guard press.modifiers.contains(.command), !runner.isRunning else { return .ignored }
            app.selectAll()
            return .handled
        }
        .onKeyPress(.upArrow) { moveSelection(-1) }
        .onKeyPress(.downArrow) { moveSelection(1) }
    }

    private var listHeader: some View {
        HStack(spacing: 9) {
            Text("Imagens adicionadas").font(.headline)
            Text(countText(app.inputs.count))
                .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
            Spacer()
            Button("Pré-visualizar", systemImage: "eye") {
                if let url = app.previewTarget { app.route = .conversionPreview(url) }
            }
            .disabled(!canPreview)
            .help([.upscale, .rename].contains(app.state.convert.mode) ? "Indisponível neste modo" : "Comparar antes e depois (barra de espaço, ⌘Y)")
            Menu {
                Button("Agrupar em subpasta de saída…") { startGrouping(app.selection) }
                    .disabled(app.selection.isEmpty)
                Button("Selecionar tudo") { app.selectAll() }
                Toggle("Mostrar pré-visualização", isOn: Binding(get: { app.state.showPreview }, set: { app.state.showPreview = $0 }))
                Divider()
                Button("Mostrar na pasta") { FilePanels.reveal(Array(app.selection)) }
                    .disabled(app.selection.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mais ações para as imagens selecionadas")
            Button("Adicionar imagens…", systemImage: "plus") { FilePanels.addFiles(to: app) }
                .disabled(runner.isRunning)
            Button("Limpar lista") { removeWithUndo(Set(app.inputs.map(\.url))) }
                .disabled(runner.isRunning)
        }
        .buttonStyle(.borderless)
        // Icon-only when the column gets narrow.
        .labelStyle(AdaptiveLabelStyle())
    }

    // MARK: Selection

    private func select(_ url: URL) {
        listFocused = true
        let flags = NSEvent.modifierFlags
        let urls = app.inputs.map(\.url)
        if flags.contains(.shift), let anchor, let a = urls.firstIndex(of: anchor), let b = urls.firstIndex(of: url) {
            app.selection = Set(urls[min(a, b)...max(a, b)])
        } else if flags.contains(.command) {
            if app.selection.contains(url) { app.selection.remove(url) } else { app.selection.insert(url) }
            anchor = url
        } else {
            app.selection = [url]
            anchor = url
        }
    }

    private func moveSelection(_ delta: Int) -> KeyPress.Result {
        let urls = app.inputs.map(\.url)
        guard !urls.isEmpty else { return .ignored }
        let current = app.selection.compactMap { urls.firstIndex(of: $0) }
        let next = min(max((delta > 0 ? current.max() : current.min()).map { $0 + delta } ?? 0, 0), urls.count - 1)
        app.selection = [urls[next]]
        anchor = urls[next]
        return .handled
    }

    // MARK: Removal with Undo

    private func removeWithUndo(_ urls: Set<URL>) {
        guard !urls.isEmpty, !runner.isRunning else { return }
        let before = app.inputs
        let selection = app.selection
        undoManager?.registerUndo(withTarget: app) { model in
            model.restore(before)
            model.selection = selection
        }
        undoManager?.setActionName(urls.count == before.count ? String(localized: "Limpar lista") : String(localized: "Remover imagens"))
        withAnimation(.snappy) { app.remove(urls) }
    }

    private func startGrouping(_ urls: Set<URL>) {
        folderTargets = urls
        folderName = ""
        askingFolderName = true
    }

    @ViewBuilder
    private func contextMenu(for url: URL) -> some View {
        let urls = app.selection.contains(url) ? app.selection : [url]
        Button("Pré-visualizar") { app.route = .conversionPreview(url) }
            .disabled(!canPreview)
        Button("Mostrar no Finder") { FilePanels.reveal(Array(urls)) }
        if let output = runner.record(for: url), output.status == .done {
            Button("Mostrar resultado no Finder") { FilePanels.reveal([output.output]) }
        }
        Divider()
        Button("Agrupar em subpasta de saída…") { startGrouping(urls) }
        let folders = Set(app.inputs.compactMap(\.virtualFolder)).sorted()
        if !folders.isEmpty {
            Menu("Mover para subpasta") {
                ForEach(folders, id: \.self) { name in Button(name) { app.move(urls, toFolder: name) } }
            }
        }
        if app.inputs.contains(where: { urls.contains($0.url) && $0.virtualFolder != nil }) {
            Button("Tirar da subpasta") { app.move(urls, toFolder: nil) }
        }
        Divider()
        Button("Remover") { removeWithUndo(urls) }
            .disabled(runner.isRunning)
    }

    // MARK: Status bar

    private var statusBar: some View {
        let total = app.totalBytes
        return HStack(spacing: 8) {
            Text(countText(app.inputs.count))
            Text("•")
            Text(app.inputs.isEmpty ? String(localized: "Pronto para começar") : String(localized: "\(formatBytes(total)) no total"))
            if !app.selection.isEmpty { Text("· \(app.selection.count) selecionada(s)") }
            if app.isScanning {
                ProgressView().controlSize(.small)
                Text("Lendo imagens…")
            }
            Spacer()
            SortMenu()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private func countText(_ n: Int) -> String {
        n == 1 ? String(localized: "1 imagem") : String(localized: "\(n) imagens")
    }
}

/// Icon + title when there is room; the icon alone otherwise.
private struct AdaptiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            Label(configuration).labelStyle(.titleAndIcon)
            configuration.icon
        }
    }
}

extension ConvertMode {
    var tabTitle: LocalizedStringKey {
        switch self {
        case .convert: "Converter"
        case .compress: "Comprimir"
        case .upscale: "AI Upscale"
        case .rename: "Renomear"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .upscale: "sparkles"
        case .rename: "character.cursor.ibeam"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .convert: "Converter imagens"
        case .compress: "Reduza o tamanho das imagens"
        case .upscale: "Amplie com inteligência artificial"
        case .rename: "Renomeie arquivos em lote"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .convert: "Converta formatos ou reduza o tamanho em poucos cliques."
        case .compress: "Comprima arquivos mantendo o formato e a melhor qualidade possível."
        case .upscale: "Aumente a resolução em até 4× recriando detalhes com IA, direto no seu Mac."
        case .rename: "Use modelos, numeração ou buscar e substituir. Os originais são renomeados."
        }
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .convert: "Converter imagens"
        case .compress: "Comprimir imagens"
        case .upscale: "Ampliar imagens"
        case .rename: "Renomear arquivos"
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
            Label(sortTitle, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("A ordem define a numeração sequencial ao renomear")
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

