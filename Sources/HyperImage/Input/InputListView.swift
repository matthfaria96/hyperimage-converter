import AppKit
import HyperImageCore
import SwiftUI

/// The files queued for conversion/renaming. Accepts drops from Finder and the sidebar.
struct InputListView: View {
    @Environment(AppModel.self) private var app
    let preview: (URL) -> Void
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var app = app
        Group {
            if app.inputs.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma imagem na lista", systemImage: "photo.stack")
                } description: {
                    Text("Arraste imagens ou pastas do Finder ou da barra lateral, ou use ⌘O.")
                } actions: {
                    Button("Adicionar Arquivos…") { FilePanels.addFiles(to: app) }
                }
            } else {
                Table(app.inputs, selection: $app.selection) {
                    TableColumn("Nome") { item in
                        HStack(spacing: 8) {
                            ThumbnailView(url: item.url, maxPixels: 64).frame(width: 28, height: 28)
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .width(min: 180, ideal: 260)
                    TableColumn("Pasta") { item in
                        Text(item.relativeDirectory ?? item.url.deletingLastPathComponent().lastPathComponent)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .width(min: 80, ideal: 140)
                    TableColumn("Dimensões") { item in DimensionsCell(url: item.url) }
                        .width(min: 80, ideal: 100)
                    TableColumn("Tamanho") { item in
                        Text(ByteCountFormatter.string(fromByteCount: BatchConverter.fileSize(item.url), countStyle: .file))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Tipo") { item in Text(item.url.pathExtension.uppercased()).foregroundStyle(.secondary) }
                        .width(min: 40, ideal: 60)
                }
                .contextMenu(forSelectionType: URL.self) { urls in
                    Button("Pré-visualizar Conversão") { if let url = urls.first { preview(url) } }
                        .disabled(urls.count != 1)
                    Button("Mostrar no Finder") { FilePanels.reveal(Array(urls)) }
                    Divider()
                    Button("Remover") { app.remove(urls) }
                    Button("Limpar Lista") { app.clear() }
                } primaryAction: { urls in
                    if let url = urls.first { preview(url) }
                }
                .onDeleteCommand { app.removeSelected() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .dropDestination(for: URL.self) { urls, _ in
            app.add(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8).allowsHitTesting(false)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(app.inputs.count == 1 ? "1 arquivo" : "\(app.inputs.count) arquivos")
            if !app.selection.isEmpty { Text("· \(app.selection.count) selecionado(s)") }
            Spacer()
            SortMenu()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct DimensionsCell: View {
    let url: URL
    @State private var text = ""

    var body: some View {
        Text(text).monospacedDigit().foregroundStyle(.secondary)
            .task(id: url) {
                let size = await Task.detached(priority: .utility) { ImageLoader.pixelSize(url) }.value
                text = size.map { "\($0.width) × \($0.height)" } ?? "—"
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
        case .none: "Sem ordenação"
        case .name: "Nome"
        case .size: "Tamanho"
        case .dateTaken: "Data da foto"
        case .type: "Tipo"
        }
        return app.state.sort.descending && app.state.sort.key != .none ? "\(name) ↓" : name
    }
}

/// Selected file preview shown at the bottom of the inspector.
struct SelectedPreview: View {
    let url: URL
    @State private var info = ""

    var body: some View {
        VStack(spacing: 6) {
            ThumbnailView(url: url, maxPixels: 480)
                .frame(maxWidth: .infinity, maxHeight: 160)
                .clipShape(.rect(cornerRadius: 8))
            Text(url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Text(info).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .task(id: url) {
            let size = await Task.detached { ImageLoader.pixelSize(url) }.value
            let bytes = ByteCountFormatter.string(fromByteCount: BatchConverter.fileSize(url), countStyle: .file)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            info = [size.map { "\($0.width) × \($0.height)" }, bytes, date?.formatted(date: .abbreviated, time: .shortened)]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }
}
