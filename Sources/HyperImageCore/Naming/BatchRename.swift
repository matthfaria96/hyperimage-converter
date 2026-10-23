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

public struct RenameMove: Equatable, Sendable {
    public let from: URL
    public let to: URL
    public init(from: URL, to: URL) { self.from = from; self.to = to }
}

public struct RenameOutcome: Sendable {
    public let renamed: Int
    public let failures: [(URL, String)]
    /// Every successful move, in order, so the rename can be undone.
    public let moved: [RenameMove]
}

/// Renames the original files in place (the "Batch Rename" tab).
public enum BatchRename {
    public static func plan(_ files: [URL], settings: BatchRenameSettings, dates: (URL) -> Date) -> [RenameEntry] {
        let needsDate = RenameTemplate.usesDate(settings.template)
        var entries: [RenameEntry] = files.enumerated().map { offset, url in
            let ext = url.pathExtension
            let base: String, newExt: String
            switch settings.method {
            case .template:
                base = RenameTemplate.render(settings.template, originalURL: url, number: settings.startNumber + offset,
                                             date: needsDate ? dates(url) : .distantPast)
                newExt = ext
            case .searchReplace:
                (base, newExt) = settings.searchReplace.apply(name: url.deletingPathExtension().lastPathComponent, ext: ext)
            }
            let finalExt = settings.extensionCase.apply(newExt)
            let name = finalExt.isEmpty ? base : "\(base).\(finalExt)"
            return RenameEntry(number: offset + 1, source: url, destination: url.deletingLastPathComponent().appendingPathComponent(name), conflict: false)
        }
        // A destination is a conflict if two entries target it, or an unrelated file already has that name.
        let sources = Set(files.map(key))
        var seen: [String: Int] = [:]
        for entry in entries { seen[key(entry.destination), default: 0] += 1 }
        entries = entries.map { entry in
            var copy = entry
            let target = key(entry.destination)
            let existsOutside = !sources.contains(target) && FileManager.default.fileExists(atPath: entry.destination.path)
            copy.conflict = !entry.unchanged && ((seen[target] ?? 0) > 1 || existsOutside)
            return copy
        }
        return blockingChains(entries)
    }

    /// Case-insensitive path key (APFS default), so `a.JPG` and `a.jpg` are the same name.
    static func key(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }

    /// A file that will not move (conflict or unchanged) keeps its name, so any entry renaming onto that
    /// name is certain to fail. Flag those too, and repeat until nothing changes (chains of renames).
    static func blockingChains(_ entries: [RenameEntry]) -> [RenameEntry] {
        var result = entries
        var blocked = Set(result.filter { $0.conflict || $0.unchanged }.map { key($0.source) })
        var changed = true
        while changed {
            changed = false
            for i in result.indices where !result[i].conflict && !result[i].unchanged
                && blocked.contains(key(result[i].destination)) && key(result[i].destination) != key(result[i].source) {
                result[i].conflict = true
                blocked.insert(key(result[i].source))
                changed = true
            }
        }
        return result
    }

    /// Two-phase move (through temporary names) so swaps like a→b, b→a work.
    /// A file is never left under its temporary name: if it cannot reach its new name nor go back to the old one,
    /// it is moved to a visible "name (HyperImage N).ext" and that move is recorded in `moved`.
    public static func execute(_ entries: [RenameEntry]) -> RenameOutcome {
        let fm = FileManager.default
        let work = entries.filter { !$0.unchanged && !$0.conflict }
        var staged: [(temp: URL, entry: RenameEntry)] = []
        var failures: [(URL, String)] = []
        for entry in work {
            let temp = temporaryURL(for: entry.source)
            do {
                try fm.moveItem(at: entry.source, to: temp)
                staged.append((temp, entry))
            } catch {
                failures.append((entry.source, error.localizedDescription))
            }
        }
        var renamed = 0
        var moved: [RenameMove] = []
        for (temp, entry) in staged {
            do {
                try fm.moveItem(at: temp, to: entry.destination)
                renamed += 1
                moved.append(RenameMove(from: entry.source, to: entry.destination))
            } catch let moveError {
                do {
                    try fm.moveItem(at: temp, to: entry.source)
                    failures.append((entry.source, moveError.localizedDescription))
                } catch {
                    if let rescued = rescue(temp, original: entry.source) {
                        moved.append(RenameMove(from: entry.source, to: rescued))
                        failures.append((entry.source, "\(moveError.localizedDescription) — o arquivo ficou em \(rescued.path)"))
                    } else {
                        failures.append((entry.source, "\(moveError.localizedDescription) — o arquivo ficou em \(temp.path)"))
                    }
                }
            }
        }
        return RenameOutcome(renamed: renamed, failures: failures, moved: moved)
    }

    /// Visible temporary name that keeps the extension, so a crash between the phases leaves usable files.
    static func temporaryURL(for source: URL) -> URL {
        let name = "hyperimage-tmp-\(UUID().uuidString)"
        let ext = source.pathExtension
        return source.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
    }

    /// Moves a stranded temporary file to the first free "name (HyperImage N).ext" next to its original.
    private static func rescue(_ temp: URL, original: URL) -> URL? {
        let fm = FileManager.default
        let folder = original.deletingLastPathComponent()
        let base = original.deletingPathExtension().lastPathComponent, ext = original.pathExtension
        for n in 1...999 {
            let name = ext.isEmpty ? "\(base) (HyperImage \(n))" : "\(base) (HyperImage \(n)).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            guard !fm.fileExists(atPath: candidate.path) else { continue }
            if (try? fm.moveItem(at: temp, to: candidate)) != nil { return candidate }
        }
        return nil
    }

    /// Reverse plan for a finished rename. Entries whose old name was taken meanwhile are flagged and skipped.
    public static func undoPlan(_ moves: [RenameMove]) -> [RenameEntry] {
        let fm = FileManager.default
        let targets = Set(moves.map { key($0.to) })
        let entries = moves.enumerated().map { i, move in
            let missing = !fm.fileExists(atPath: move.to.path)
            // A name held by another renamed file counts as free only if that file moves away (checked below).
            let taken = fm.fileExists(atPath: move.from.path) && !targets.contains(key(move.from))
            return RenameEntry(number: i + 1, source: move.to, destination: move.from, conflict: missing || taken)
        }
        return blockingChains(entries)
    }
}
