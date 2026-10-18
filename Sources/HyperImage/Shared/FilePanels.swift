import AppKit
import HyperImageCore
import UniformTypeIdentifiers

enum FilePanels {
    static func addFiles(to model: AppModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Adicionar"
        if panel.runModal() == .OK { model.add(panel.urls) }
    }

    static func chooseFolder(startingAt path: String = "", prompt: String = "Escolher") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = prompt
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Escolher"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static let optionsType = UTType(exportedAs: "com.hyperimage.options", conformingTo: .json)

    static func saveOptions(_ options: AdvancedOptions) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [optionsType]
        panel.nameFieldStringValue = "Opções.hyperoptions"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try options.save(to: url)
    }

    static func loadOptions() throws -> AdvancedOptions? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [optionsType, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try AdvancedOptions.load(from: url)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
