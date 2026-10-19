import Foundation
import HyperImageCore
import Testing
@testable import HyperImage

/// Copies the fixtures into a fresh folder, so tests can write next to them.
struct Workspace {
    let root: URL
    let images: [URL]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hyperimage-app-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Fotos/Praia", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        images = try ["paisagem", "retrato"].map { name in
            let source = try #require(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"))
            let target = photos.appendingPathComponent("\(name).jpg")
            try FileManager.default.copyItem(at: source, to: target)
            return target
        }
        try Data("não é imagem".utf8).write(to: photos.appendingPathComponent("leia-me.txt"))
    }

    var output: URL { root.appendingPathComponent("Saída", isDirectory: true) }
}

@Suite(.serialized)
struct InputListFlowTests {
    @Test func addingFilesAndFolders() throws {
        let ws = try Workspace()
        let app = AppModel()
        app.add([ws.root.appendingPathComponent("Fotos")])
        #expect(app.inputs.count == 2)
        #expect(app.inputs.allSatisfy { $0.relativeDirectory == "Fotos/Praia" })
        #expect(app.hasFolderItems)

        app.add(ws.images) // duplicates are ignored
        #expect(app.inputs.count == 2)

        let kept = app.inputs[1].url
        app.remove([app.inputs[0].url])
        #expect(app.inputs.map(\.url) == [kept])
        app.clear()
        #expect(app.inputs.isEmpty && app.selection.isEmpty)
    }

    @Test func virtualFolders() throws {
        let ws = try Workspace()
        let app = AppModel()
        app.add(ws.images)
        let first = app.inputs[0].url
        app.move([first], toFolder: "Melhores")
        #expect(app.inputs.first { $0.url == first }?.virtualFolder == "Melhores")
        #expect(app.inputs.filter { $0.virtualFolder != nil }.count == 1)

        app.move([first], toFolder: nil)
        #expect(app.inputs.allSatisfy { $0.virtualFolder == nil })
    }
}

@Suite(.serialized)
struct ConversionFlowTests {
    func settings(output: URL) -> ConvertSettings {
        var s = ConvertSettings()
        s.format = .png
        s.outputFolder = output.path
        s.parallel = false
        return s
    }

    func waitUntilDone(_ runner: ConversionRunner, answering decision: OverwriteDecision? = nil) async throws {
        for _ in 0..<600 {
            if let decision, runner.prompt != nil { runner.answer(decision) }
            if !runner.isRunning { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("conversion did not finish")
    }

    @Test func convertsIntoOutputFolderKeepingStructure() async throws {
        let ws = try Workspace()
        let app = AppModel()
        app.add([ws.root.appendingPathComponent("Fotos")])
        let runner = ConversionRunner()
        runner.start(items: app.inputs, settings: settings(output: ws.output))
        try await waitUntilDone(runner)

        #expect(!runner.wasCancelled)
        #expect(runner.records.allSatisfy { $0.status == .done })
        #expect(runner.progress == 1)
        for name in ["paisagem", "retrato"] {
            #expect(FileManager.default.fileExists(atPath: ws.output.appendingPathComponent("Fotos/Praia/\(name).png").path))
        }
    }

    @Test(arguments: [(OverwriteDecision.yesToAll, ConversionStatus.done), (.noToAll, .skipped)])
    func existingOutputsAskBeforeOverwriting(decision: OverwriteDecision, expected: ConversionStatus) async throws {
        let ws = try Workspace()
        let runner = ConversionRunner()
        let items = ws.images.map { InputItem(url: $0) }
        runner.start(items: items, settings: settings(output: ws.output))
        try await waitUntilDone(runner)

        runner.start(items: items, settings: settings(output: ws.output))
        try await waitUntilDone(runner, answering: decision)
        #expect(runner.records.map(\.status) == [expected, expected])
        #expect(!runner.wasCancelled)
    }

    @Test func cancellingFromThePromptStopsTheBatch() async throws {
        let ws = try Workspace()
        let runner = ConversionRunner()
        let items = ws.images.map { InputItem(url: $0) }
        runner.start(items: items, settings: settings(output: ws.output))
        try await waitUntilDone(runner)

        runner.start(items: items, settings: settings(output: ws.output))
        try await waitUntilDone(runner, answering: .cancel)
        #expect(runner.wasCancelled)
        #expect(runner.records.allSatisfy { $0.status == .pending })
    }

    @Test func virtualFolderAndLosslessCropEndToEnd() async throws {
        let ws = try Workspace()
        var s = settings(output: ws.output)
        s.format = .jpeg
        s.useAdvancedOptions = true
        s.advanced.crop.enabled = true
        let runner = ConversionRunner()
        runner.start(items: [InputItem(url: ws.images[0]).inFolder("Recortes")], settings: s)
        try await waitUntilDone(runner)

        let out = ws.output.appendingPathComponent("Recortes/paisagem.jpg")
        let size = try #require(ImageLoader.pixelSize(out))
        #expect(size == PixelSize(width: 640, height: 480))
    }
}

struct PersistenceTests {
    @Test func settingsSurviveMissingKeys() throws {
        var state = PersistedState()
        state.convert.formatSettings.jpeg.quality = 42
        state.showPreview = false
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        // Simulate a file saved before these options existed.
        json["sort"] = nil
        var convert = try #require(json["convert"] as? [String: Any])
        convert["keepDates"] = nil
        json["convert"] = convert
        let restored = PersistedState.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(restored.convert.formatSettings.jpeg.quality == 42)
        #expect(restored.showPreview == false)
        #expect(restored.sort == InputSort())
    }
}
