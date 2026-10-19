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
    public var uppercaseExtension = false
    public var keepDates = true
    public var askBeforeOverwrite = true
    public var showErrors = true
    public var parallel = true
    public var openFolderWhenDone = false
    /// Simplified window: convert to `format`, or compress keeping each file's own format.
    public var mode = ConvertMode.convert
    /// Off: shrink images whose long side exceeds `maxLongSide` (unless Advanced Options already resize).
    public var keepDimensions = true
    public var maxLongSide = 2400
    /// Lower the quality of lossy formats until each file fits under `maxFileSizeKB`.
    public var limitFileSize = false
    public var maxFileSizeKB = 500
    public var preserveTransparency = true
    /// Appends "-convertido" / "-comprimido" to output names.
    public var addSuffix = false
    /// Existing outputs are left alone without asking.
    public var skipExisting = false
    public var upscale = UpscaleSettings()

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
    /// "Create Folder" in the input list: the output goes into a subfolder with this name.
    public let virtualFolder: String?

    public init(url: URL, relativeDirectory: String? = nil, virtualFolder: String? = nil) {
        self.url = url
        self.relativeDirectory = relativeDirectory
        self.virtualFolder = virtualFolder
    }

    public func inFolder(_ name: String?) -> InputItem {
        InputItem(url: url, relativeDirectory: relativeDirectory, virtualFolder: name)
    }

    /// A usable single-level folder name, or nil (empty, ".", "..", or containing "/" or ":").
    public static func folderName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else { return nil }
        return name
    }
}

public enum OutputPlanner {
    /// Destination for each item, in order. Names produced twice within the batch get a numeric suffix.
    public static func destinations(for items: [InputItem], settings: ConvertSettings) -> [URL] {
        // Other inputs are reserved so an output can never replace a file that has not been read yet.
        let inputPaths = items.map { $0.url.standardizedFileURL.path.lowercased() }
        var used = Set(inputPaths)
        return items.enumerated().map { offset, item in
            let format = settings.outputFormat(for: item.url)
            let ext = settings.uppercaseExtension ? format.fileExtension.uppercased() : format.fileExtension
            var folder = settings.outputFolderURL ?? item.url.deletingLastPathComponent()
            if let virtual = item.virtualFolder {
                folder = folder.appendingPathComponent(virtual, isDirectory: true)
            } else if settings.outputFolderURL != nil, settings.keepFolderStructure, let relative = item.relativeDirectory, !relative.isEmpty {
                folder = folder.appendingPathComponent(relative, isDirectory: true)
            }
            let base = item.url.deletingPathExtension().lastPathComponent + settings.nameSuffix
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
