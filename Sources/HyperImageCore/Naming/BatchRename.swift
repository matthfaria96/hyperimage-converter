import Foundation

public enum RenameMethod: String, Codable, CaseIterable, Sendable {
    case template, searchReplace
}

public struct BatchRenameSettings: Codable, Equatable, Sendable {
    public var method = RenameMethod.template
    public var template = "Image#####"
    public var startNumber = 1
    public var extensionCase = ExtensionCase.noChange
    public var searchReplace = SearchReplaceRule()

    public init() {}
}

public struct RenameEntry: Identifiable, Equatable, Sendable {
    public var id: URL { source }
    public let number: Int
    public let source: URL
    public let destination: URL
    public var conflict: Bool

    public var unchanged: Bool { source == destination }
}

public struct RenameOutcome: Sendable {
    public let renamed: Int
    public let failures: [(URL, String)]
}

/// Renames the original files in place (the "Batch Rename" tab).
public enum BatchRename {
    public static func plan(_ files: [URL], settings: BatchRenameSettings, dates: (URL) -> Date) -> [RenameEntry] {
        var entries: [RenameEntry] = files.enumerated().map { offset, url in
            let ext = url.pathExtension
            let base: String, newExt: String
            switch settings.method {
            case .template:
                base = RenameTemplate.render(settings.template, originalURL: url, number: settings.startNumber + offset, date: dates(url))
                newExt = ext
            case .searchReplace:
                (base, newExt) = settings.searchReplace.apply(name: url.deletingPathExtension().lastPathComponent, ext: ext)
            }
            let finalExt = settings.extensionCase.apply(newExt)
            let name = finalExt.isEmpty ? base : "\(base).\(finalExt)"
            return RenameEntry(number: offset + 1, source: url, destination: url.deletingLastPathComponent().appendingPathComponent(name), conflict: false)
        }
        // A destination is a conflict if two entries target it, or an unrelated file already has that name.
        let sources = Set(files.map { $0.standardizedFileURL.path.lowercased() })
        var seen: [String: Int] = [:]
        for entry in entries { seen[entry.destination.standardizedFileURL.path.lowercased(), default: 0] += 1 }
        entries = entries.map { entry in
            var copy = entry
            let key = entry.destination.standardizedFileURL.path.lowercased()
            let existsOutside = !sources.contains(key) && FileManager.default.fileExists(atPath: entry.destination.path)
            copy.conflict = !entry.unchanged && ((seen[key] ?? 0) > 1 || existsOutside)
            return copy
        }
        return entries
    }

    /// Two-phase move (through temporary names) so swaps like a→b, b→a work.
    public static func execute(_ entries: [RenameEntry]) -> RenameOutcome {
        let fm = FileManager.default
        let work = entries.filter { !$0.unchanged && !$0.conflict }
        var staged: [(temp: URL, entry: RenameEntry)] = []
        var failures: [(URL, String)] = []
        for entry in work {
            let temp = entry.source.deletingLastPathComponent().appendingPathComponent(".hyperimage-\(UUID().uuidString)")
            do {
                try fm.moveItem(at: entry.source, to: temp)
                staged.append((temp, entry))
            } catch {
                failures.append((entry.source, error.localizedDescription))
            }
        }
        var renamed = 0
        for (temp, entry) in staged {
            do {
                try fm.moveItem(at: temp, to: entry.destination)
                renamed += 1
            } catch {
                do {
                    try fm.moveItem(at: temp, to: entry.source)
                    failures.append((entry.source, error.localizedDescription))
                } catch let restoreError {
                    failures.append((temp, "\(error.localizedDescription) — o arquivo ficou em \(temp.path): \(restoreError.localizedDescription)"))
                }
            }
        }
        return RenameOutcome(renamed: renamed, failures: failures)
    }
}
