import AppKit
import HyperImageCore
import Observation

/// Shared window state: the input list and all persisted settings.
@Observable
final class AppModel {
    var state: PersistedState {
        didSet { if state != oldValue { scheduleSave() } }
    }
    private(set) var inputs: [InputItem] = [] {
        didSet { inputsRevision += 1; refreshTotal() }
    }
    /// Changes whenever the list does; cheap for views to watch instead of comparing every URL.
    private(set) var inputsRevision = 0
    /// Combined size of the queued files, summed off the main thread.
    private(set) var totalBytes: Int64 = 0
    @ObservationIgnored private var totalTask: Task<Void, Never>?
    var selection: Set<URL> = []
    var alert: AppAlert?
    /// Sheet shown over the main window; menu commands set it too.
    var route: SheetRoute?
    /// Moves of the last rename, kept so it can be undone. Not persisted.
    var lastRename: [RenameMove] = []
    /// Bumped by the "Converter" menu command; MainView starts the batch when it changes.
    var startRequest = 0
    /// Set while a batch runs, so menu commands can disable themselves.
    var isBusy = false
    /// True while files or folders are being scanned in the background.
    private(set) var isScanning = false
    private var scanCount = 0

    private var saveTask: Task<Void, Never>?

    init() {
        state = PersistedState.load()
    }

    private func refreshTotal() {
        totalTask?.cancel()
        let urls = inputs.map(\.url)
        totalTask = Task {
            let sum = await Task.detached(priority: .utility) { urls.reduce(Int64(0)) { $0 + InputSort.cachedSize(of: $1) } }.value
            guard !Task.isCancelled else { return }
            totalBytes = sum
        }
    }

    var selectedItem: InputItem? {
        guard selection.count == 1, let url = selection.first else { return nil }
        return inputs.first { $0.url == url }
    }

    var hasFolderItems: Bool { inputs.contains { $0.relativeDirectory != nil } }

    // MARK: Input list

    /// Adds files and folders (folders contribute their images recursively). Duplicates are ignored.
    /// Synchronous; the app itself uses `addInBackground` so big folders never freeze the window.
    func add(_ urls: [URL]) {
        let added = Self.scan(urls, existing: inputs.map(\.url))
        guard !added.isEmpty else { return }
        inputs = state.sort.sorted(inputs + added)
    }

    /// Walks folders, reads sort keys and deduplicates off the main thread; only the final merge runs here.
    func addInBackground(_ urls: [URL]) {
        let existing = inputs.map(\.url)
        let sort = state.sort
        scanCount += 1
        isScanning = true
        Task {
            let added = await Task.detached(priority: .userInitiated) { () -> [InputItem] in
                let found = Self.scan(urls, existing: existing)
                sort.prewarm(found)
                return found
            }.value
            scanCount -= 1
            isScanning = scanCount > 0
            guard !added.isEmpty else { return }
            // Everything is cached by now, so this sort does no disk access.
            let current = Set(inputs.map { Self.identity($0.url) })
            let fresh = added.filter { !current.contains(Self.identity($0.url)) }
            inputs = state.sort.sorted(inputs + fresh)
        }
    }

    nonisolated private static func scan(_ urls: [URL], existing: [URL]) -> [InputItem] {
        var known = Set(existing.map(identity))
        var added: [InputItem] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let items = isDirectory.boolValue
                ? ImageFileTypes.images(in: url).map { InputItem(url: $0.url, relativeDirectory: $0.relativeDirectory) }
                : (ImageFileTypes.isImage(url) ? [InputItem(url: url)] : [])
            for item in items where !known.contains(identity(item.url)) {
                known.insert(identity(item.url))
                added.append(item)
            }
        }
        return added
    }

    /// Same file reached through a symlink (/var vs /private/var) or "..": one entry only.
    nonisolated private static func identity(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    func removeSelected() {
        inputs = inputs.filter { !selection.contains($0.url) }
        selection = []
    }

    func remove(_ urls: Set<URL>) {
        inputs = inputs.filter { !urls.contains($0.url) }
        selection.subtract(urls)
    }

    func clear() {
        inputs = []
        selection = []
    }

    /// Puts back a list saved before a removal (Undo).
    func restore(_ items: [InputItem]) {
        inputs = items
        selection.formIntersection(Set(items.map(\.url)))
    }

    func selectAll() { selection = Set(inputs.map(\.url)) }

    /// URL of the item to preview: the single selection, else the first file.
    var previewTarget: URL? { selectedItem?.url ?? inputs.first?.url }

    /// Puts the files into a virtual output folder (nil takes them out again).
    func move(_ urls: Set<URL>, toFolder name: String?) {
        inputs = inputs.map { urls.contains($0.url) ? $0.inFolder(name) : $0 }
    }

    /// Points the list (and selection) at renamed files.
    func replace(_ mapping: [URL: URL]) {
        inputs = inputs.map { item in
            guard let moved = mapping[item.url] else { return item }
            return InputItem(url: moved, relativeDirectory: item.relativeDirectory, virtualFolder: item.virtualFolder)
        }
        selection = Set(selection.map { mapping[$0] ?? $0 })
    }

    func setSort(_ sort: InputSort) {
        state.sort = sort
        let items = inputs
        guard sort.key == .size || sort.key == .dateTaken else { inputs = sort.sorted(items); return }
        // Reading every file's date can take seconds on a long list: do it in the background, then reorder.
        scanCount += 1
        isScanning = true
        Task {
            await Task.detached(priority: .userInitiated) { sort.prewarm(items) }.value
            scanCount -= 1
            isScanning = scanCount > 0
            if state.sort == sort { inputs = sort.sorted(inputs) }
        }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.state.save()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        state.save()
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
