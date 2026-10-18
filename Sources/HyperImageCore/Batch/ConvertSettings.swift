import Foundation

/// Everything on the Batch Convert tab. Persisted between launches.
public struct ConvertSettings: Codable, Equatable, Sendable {
    public var format = OutputFormat.jpeg
    public var formatSettings = FormatSettings()
    public var useOutputFolder = true
    public var outputFolder = ""
    public var keepFolderStructure = true
    public var useAdvancedOptions = false
    public var advanced = AdvancedOptions()
    public var rename = false
    public var renameTemplate = "Image#####"
    public var renameStartNumber = 1
    public var uppercaseExtension = false
    public var keepDates = true
    public var askBeforeOverwrite = true
    public var showErrors = true
    public var parallel = true
    public var openFolderWhenDone = false

    public init() {}

    public var outputFolderURL: URL? {
        guard useOutputFolder, !outputFolder.isEmpty else { return nil }
        return URL(fileURLWithPath: (outputFolder as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// One file queued for conversion. `relativeDirectory` is set for files that came from an added folder.
public struct InputItem: Hashable, Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let relativeDirectory: String?

    public init(url: URL, relativeDirectory: String? = nil) {
        self.url = url
        self.relativeDirectory = relativeDirectory
    }
}

public enum OutputPlanner {
    /// Destination for each item, in order. Names produced twice within the batch get a numeric suffix.
    public static func destinations(for items: [InputItem], settings: ConvertSettings, dates: (URL) -> Date) -> [URL] {
        // Other inputs are reserved so an output can never replace a file that has not been read yet.
        let inputPaths = items.map { $0.url.standardizedFileURL.path.lowercased() }
        var used = Set(inputPaths)
        let ext = settings.uppercaseExtension ? settings.format.fileExtension.uppercased() : settings.format.fileExtension
        return items.enumerated().map { offset, item in
            var folder = settings.outputFolderURL ?? item.url.deletingLastPathComponent()
            if settings.outputFolderURL != nil, settings.keepFolderStructure, let relative = item.relativeDirectory, !relative.isEmpty {
                folder = folder.appendingPathComponent(relative, isDirectory: true)
            }
            let base = settings.rename
                ? RenameTemplate.render(settings.renameTemplate, originalURL: item.url, number: settings.renameStartNumber + offset, date: dates(item.url))
                : item.url.deletingPathExtension().lastPathComponent
            let own = inputPaths[offset]
            var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
            var counter = 2
            while used.contains(candidate.standardizedFileURL.path.lowercased()) && candidate.standardizedFileURL.path.lowercased() != own {
                candidate = folder.appendingPathComponent("\(base)-\(counter)").appendingPathExtension(ext)
                counter += 1
            }
            used.insert(candidate.standardizedFileURL.path.lowercased())
            return candidate
        }
    }
}
