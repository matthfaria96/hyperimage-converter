import AppKit
import HyperImageCore
import Observation

nonisolated struct BrowserEntry: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modified: Date?

    var name: String { url.lastPathComponent }
}

/// Contents of the folder shown in the sidebar browser.
@Observable
final class BrowserModel {
    private(set) var folder: URL
    private(set) var entries: [BrowserEntry] = []
    var selection: Set<URL> = []
    var filter: FileTypeFilter
    private var loadTask: Task<Void, Never>?

    init(path: String, filterName: String) {
        folder = URL(fileURLWithPath: path, isDirectory: true)
        filter = ImageFileTypes.filters.first { $0.name == filterName } ?? ImageFileTypes.filters[0]
    }

    var files: [BrowserEntry] { entries.filter { !$0.isDirectory } }
    var folderCount: Int { entries.count - files.count }

    var ancestors: [URL] {
        var list: [URL] = []
        var url = folder.standardizedFileURL
        while true {
            list.append(url)
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return list
    }

    func open(_ url: URL) {
        folder = url.standardizedFileURL
        selection = []
        reload()
    }

    func goUp() {
        let parent = folder.deletingLastPathComponent()
        if parent.path != folder.path { open(parent) }
    }

    func setFilter(_ newFilter: FileTypeFilter) {
        filter = newFilter
        reload()
    }

    func reload() {
        loadTask?.cancel()
        let folder = folder, filter = filter
        loadTask = Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) { Self.list(folder, filter: filter) }.value
            guard !Task.isCancelled else { return }
            self?.entries = entries
        }
    }

    nonisolated private static func list(_ folder: URL, filter: FileTypeFilter) -> [BrowserEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let entries = urls.compactMap { url -> BrowserEntry? in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
            guard isDirectory || filter.matches(url) else { return nil }
            return BrowserEntry(url: url, isDirectory: isDirectory, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate)
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
