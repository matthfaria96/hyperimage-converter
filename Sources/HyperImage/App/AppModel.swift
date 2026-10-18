import AppKit
import HyperImageCore
import Observation

/// Shared window state: the input list and all persisted settings.
@Observable
final class AppModel {
    var state: PersistedState {
        didSet { if state != oldValue { scheduleSave() } }
    }
    private(set) var inputs: [InputItem] = []
    var selection: Set<URL> = []
    var alert: AppAlert?

    private var saveTask: Task<Void, Never>?

    init() {
        state = PersistedState.load()
    }

    var selectedItem: InputItem? {
        guard selection.count == 1, let url = selection.first else { return nil }
        return inputs.first { $0.url == url }
    }

    var hasFolderItems: Bool { inputs.contains { $0.relativeDirectory != nil } }

    // MARK: Input list

    /// Adds files and folders (folders contribute their images recursively). Duplicates are ignored.
    func add(_ urls: [URL]) {
        var known = Set(inputs.map { Self.identity($0.url) })
        var added: [InputItem] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let items = isDirectory.boolValue
                ? ImageFileTypes.images(in: url).map { InputItem(url: $0.url, relativeDirectory: $0.relativeDirectory) }
                : (ImageFileTypes.isImage(url) ? [InputItem(url: url)] : [])
            for item in items where !known.contains(Self.identity(item.url)) {
                known.insert(Self.identity(item.url))
                added.append(item)
            }
        }
        guard !added.isEmpty else { return }
        inputs = state.sort.sorted(inputs + added)
    }

    /// Same file reached through a symlink (/var vs /private/var) or "..": one entry only.
    private static func identity(_ url: URL) -> String {
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

    /// Puts the files into a virtual output folder (nil takes them out again).
    func move(_ urls: Set<URL>, toFolder name: String?) {
        inputs = inputs.map { urls.contains($0.url) ? $0.inFolder(name) : $0 }
    }

    func setSort(_ sort: InputSort) {
        state.sort = sort
        inputs = sort.sorted(inputs)
    }

    /// After a batch rename the files moved; keep the list pointing at them.
    func replace(_ mapping: [URL: URL]) {
        inputs = inputs.map { item in
            guard let moved = mapping[item.url] else { return item }
            return InputItem(url: moved, relativeDirectory: item.relativeDirectory, virtualFolder: item.virtualFolder)
        }
        selection = Set(selection.map { mapping[$0] ?? $0 })
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
