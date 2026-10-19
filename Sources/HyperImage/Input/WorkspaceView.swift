import AppKit
import HyperImageCore
import SwiftUI

/// Left side of the window: mode tabs, drop area and the queued files as cards.
struct WorkspaceView: View {
    @Environment(AppModel.self) private var app
    let runner: ConversionRunner
    let preview: (URL) -> Void
    @State private var dropTargeted = false
    @State private var folderTargets: Set<URL> = []
    @State private var folderName = ""
    @State private var askingFolderName = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if app.inputs.isEmpty {
                    EmptyDropZone(targeted: dropTargeted) { FilePanels.addFiles(to: app) }
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
            return withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { app.add(urls); return true }
        } isTargeted: { dropTargeted = $0 && !runner.isRunning }
        .overlay {
            if dropTargeted && !app.inputs.isEmpty { DropOverlay() }
        }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .onDeleteCommand { app.removeSelected() }
        .alert("Nova pasta", isPresented: $askingFolderName) {
            TextField("Nome da pasta", text: $folderName)
            Button("Cancelar", role: .cancel) {}
            Button("Criar") { app.move(folderTargets, toFolder: InputItem.folderName(folderName)) }
                .disabled(InputItem.folderName(folderName) == nil)
        } message: {
            Text("Os arquivos selecionados serão salvos numa subpasta com este nome dentro da pasta de saída.")
        }
        #if DEBUG
        .onAppear { if DebugLaunch.env["HYPERIMAGE_DROP"] != nil { dropTargeted = true } }
        #endif
    }

    // MARK: Header

    private var header: some View {
        @Bindable var app = app
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.state.convert.mode.title).font(.title2.weight(.bold))
                    .contentTransition(.opacity)
                Text(app.state.convert.mode.subtitle).font(.callout).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Picker("Modo", selection: $app.state.convert.mode.animation(.snappy)) {
                ForEach(ConvertMode.allCases, id: \.self) { mode in
                    Label(mode.tabTitle, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(runner.isRunning)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    // MARK: Files

    private var fileList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CompactDropZone(targeted: dropTargeted) { FilePanels.addFiles(to: app) }
                HStack(spacing: 9) {
                    Text("Arquivos selecionados").font(.headline)
                    Text(countText(app.inputs.count))
                        .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                    Spacer()
                    if app.state.convert.mode != .upscale {
                        Button("Pré-visualizar", systemImage: "eye") {
                            if let url = app.selectedItem?.url ?? app.inputs.first?.url { preview(url) }
                        }
                        .help("Comparar antes e depois (duplo clique num arquivo)")
                    }
                    Button("Adicionar", systemImage: "plus") { FilePanels.addFiles(to: app) }
                        .disabled(runner.isRunning)
                    Button("Limpar lista") { withAnimation { app.clear() } }
                        .disabled(runner.isRunning)
                }
                .buttonStyle(.borderless)
                LazyVStack(spacing: 7) {
                    ForEach(app.inputs) { item in
                        FileCard(item: item, record: runner.record(for: item.url), isRunning: runner.isRunning,
                                 isSelected: app.selection.contains(item.url),
                                 showsRatio: app.state.convert.mode != .upscale,
                                 working: runner.currentUpscale == item.url ? runner.partial : nil) {
                            withAnimation(.snappy) { app.remove([item.url]) }
                        }
                        .disabled(runner.isRunning)
                        .onTapGesture { select(item.url) }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            if app.state.convert.mode != .upscale { preview(item.url) }
                        })
                        .contextMenu { contextMenu(for: item.url) }
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity.combined(with: .scale(scale: 0.96))))
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
    }

    private func select(_ url: URL) {
        if NSEvent.modifierFlags.contains(.command) {
            if app.selection.contains(url) { app.selection.remove(url) } else { app.selection.insert(url) }
        } else {
            app.selection = app.selection == [url] ? [] : [url]
        }
    }

    @ViewBuilder
    private func contextMenu(for url: URL) -> some View {
        let urls = app.selection.contains(url) ? app.selection : [url]
        Button("Pré-visualizar Conversão") { preview(url) }
            .disabled(app.state.convert.mode == .upscale)
        Button("Mostrar no Finder") { FilePanels.reveal(Array(urls)) }
        if let output = runner.record(for: url), output.status == .done {
            Button("Mostrar Resultado no Finder") { FilePanels.reveal([output.output]) }
        }
        Divider()
        Button("Criar Pasta…") {
            folderTargets = urls
            folderName = ""
            askingFolderName = true
        }
        let folders = Set(app.inputs.compactMap(\.virtualFolder)).sorted()
        if !folders.isEmpty {
            Menu("Mover para Pasta") {
                ForEach(folders, id: \.self) { name in Button(name) { app.move(urls, toFolder: name) } }
            }
        }
        if app.inputs.contains(where: { urls.contains($0.url) && $0.virtualFolder != nil }) {
            Button("Tirar da Pasta") { app.move(urls, toFolder: nil) }
        }
        Divider()
        Button("Remover") { withAnimation(.snappy) { app.remove(urls) } }
            .disabled(runner.isRunning)
    }

    // MARK: Status bar

    private var statusBar: some View {
        let total = app.inputs.reduce(Int64(0)) { $0 + BatchConverter.fileSize($1.url) }
        return HStack(spacing: 8) {
            Text(countText(app.inputs.count))
            Text("•")
            Text(app.inputs.isEmpty ? String(localized: "Pronto para começar") : String(localized: "\(formatBytes(total)) no total"))
            if !app.selection.isEmpty { Text("· \(app.selection.count) selecionado(s)") }
            Spacer()
            SortMenu()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private func countText(_ n: Int) -> String {
        n == 1 ? String(localized: "1 arquivo") : String(localized: "\(n) arquivos")
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
        case .convert: "Prepare suas imagens"
        case .compress: "Reduza o tamanho das imagens"
        case .upscale: "Amplie com inteligência artificial"
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
                Text("Sem ordenação").tag(InputSortKey.none)
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
        case .none: String(localized: "Sem ordenação")
        case .name: String(localized: "Nome")
        case .size: String(localized: "Tamanho")
        case .dateTaken: String(localized: "Data da foto")
        case .type: String(localized: "Tipo")
        }
        return app.state.sort.descending && app.state.sort.key != .none ? "\(name) ↓" : name
    }
}

