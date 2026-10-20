import AppKit
import HyperImageCore
import SwiftUI

/// Sidebar: a Finder-style browser whose files can be added or dragged into the input list.
struct BrowserView: View {
    @Environment(AppModel.self) private var app
    @Bindable var browser: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            BrowserHeader(browser: browser)
            Divider()
            content
            Divider()
            footer
        }
        .onChange(of: browser.folder) { _, folder in app.state.browserPath = folder.path }
    }

    @ViewBuilder
    private var content: some View {
        if app.state.browserLayout == .list {
            List(browser.entries, selection: $browser.selection) { entry in
                BrowserRow(entry: entry)
                    .draggable(entry.url)
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                menu(for: urls)
            } primaryAction: { urls in
                activate(urls)
            }
        } else {
            BrowserGrid(browser: browser, activate: activate)
        }
    }

    @ViewBuilder
    private func menu(for urls: Set<URL>) -> some View {
        Button("Adicionar à lista") { app.addInBackground(Array(urls)) }
        Button("Abrir no Visualizador") { urls.forEach { NSWorkspace.shared.open($0) } }
        Button("Mostrar no Finder") { FilePanels.reveal(Array(urls)) }
        Divider()
        Button("Atualizar") { browser.reload() }
    }

    private func activate(_ urls: Set<URL>) {
        if urls.count == 1, let url = urls.first, browser.entries.first(where: { $0.url == url })?.isDirectory == true {
            browser.open(url)
        } else {
            app.addInBackground(Array(urls))
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Adicionar", systemImage: "plus") { app.addInBackground(Array(browser.selection)) }
                    .disabled(browser.selection.isEmpty)
                Button("Adicionar todas", systemImage: "plus.square.on.square") { app.addInBackground(browser.files.map(\.url)) }
                    .disabled(browser.files.isEmpty)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            HStack {
                Picker("Tipo", selection: Binding(get: { browser.filter }, set: { browser.setFilter($0); app.state.filterName = $0.name })) {
                    ForEach(ImageFileTypes.filters) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                Spacer()
                Text("\(browser.folderCount) pastas, \(browser.files.count) arquivos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
    }
}

private struct BrowserHeader: View {
    @Environment(AppModel.self) private var app
    let browser: BrowserModel

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(browser.ancestors, id: \.self) { url in
                    Button { browser.open(url) } label: {
                        Label(FileManager.default.displayName(atPath: url.path), systemImage: "folder")
                    }
                }
                Divider()
                ForEach(Locations.all, id: \.self) { url in
                    Button(FileManager.default.displayName(atPath: url.path)) { browser.open(url) }
                }
            } label: {
                Label(FileManager.default.displayName(atPath: browser.folder.path), systemImage: "folder.fill")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .help(browser.folder.path)
            Spacer(minLength: 4)
            Button("Subir", systemImage: "chevron.up") { browser.goUp() }
            Button("Atualizar", systemImage: "arrow.clockwise") { browser.reload() }
            Button("Escolher Pasta", systemImage: "folder.badge.plus") {
                if let url = FilePanels.chooseFolder(startingAt: browser.folder.path) { browser.open(url) }
            }
            Picker("Visualização", selection: Binding(get: { app.state.browserLayout }, set: { app.state.browserLayout = $0 })) {
                Image(systemName: "list.bullet").tag(BrowserLayout.list)
                Image(systemName: "square.grid.2x2").tag(BrowserLayout.thumbnails)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

enum Locations {
    static var all: [URL] {
        let fm = FileManager.default
        let dirs: [FileManager.SearchPathDirectory] = [.desktopDirectory, .downloadsDirectory, .picturesDirectory, .documentDirectory]
        return [fm.homeDirectoryForCurrentUser] + dirs.compactMap { fm.urls(for: $0, in: .userDomainMask).first }
            + [URL(fileURLWithPath: "/Volumes")]
    }
}

private struct BrowserRow: View {
    let entry: BrowserEntry

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if entry.isDirectory {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable()
                } else {
                    ThumbnailView(url: entry.url, maxPixels: 64)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                if !entry.isDirectory {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
        guard let date = entry.modified else { return size }
        return "\(size) · \(date.formatted(date: .numeric, time: .shortened))"
    }
}

private struct BrowserGrid: View {
    @Bindable var browser: BrowserModel
    let activate: (Set<URL>) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(browser.entries) { entry in
                    let selected = browser.selection.contains(entry.url)
                    VStack(spacing: 4) {
                        Group {
                            if entry.isDirectory {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().scaledToFit()
                            } else {
                                ThumbnailView(url: entry.url, maxPixels: 200)
                            }
                        }
                        .frame(width: 80, height: 64)
                        Text(entry.name).font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                    .padding(6)
                    .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                    .draggable(entry.url)
                    .onTapGesture(count: 2) { activate([entry.url]) }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            browser.selection.formSymmetricDifference([entry.url])
                        } else {
                            browser.selection = [entry.url]
                        }
                    }
                }
            }
            .padding(8)
        }
    }
}
