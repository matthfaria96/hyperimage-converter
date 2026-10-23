import Foundation
import HyperImageCore
import Testing
@testable import HyperImage

/// Copies the fixtures into a fresh folder, so tests can write next to them.
final class Workspace {
    let root: URL
    let images: [URL]

    deinit { try? FileManager.default.removeItem(at: root) }

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

    @Test func renamesOutputsByTemplate() async throws {
        let ws = try Workspace()
        var s = settings(output: ws.output)
        s.format = .jpeg
        s.rename = true
        s.renameTemplate = "Praia_##"
        s.renameStartNumber = 1
        let sizes = try ws.images.map { try #require(FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) }
        let runner = ConversionRunner()
        runner.start(items: ws.images.map { InputItem(url: $0) }, settings: s)
        try await waitUntilDone(runner)

        for name in ["Praia_01.jpg", "Praia_02.jpg"] {
            #expect(FileManager.default.fileExists(atPath: ws.output.appendingPathComponent(name).path))
        }
        let after = ws.images.map { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int }
        #expect(after == sizes.map { Optional($0) })
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

    @Test(arguments: [0, 1, 5])
    func searchReplacePairsAreNormalized(count: Int) throws {
        var state = PersistedState()
        state.rename.searchReplace.pairs = (0..<count).map { SearchReplaceRule.Pair(search: "s\($0)") }
        let restored = PersistedState.decode(try JSONEncoder().encode(state))
        #expect(restored.rename.searchReplace.pairs.count == SearchReplaceRule.pairCount)
        #expect(restored.rename.searchReplace.pairs.prefix(min(count, 3)).map(\.search) == (0..<min(count, 3)).map { "s\($0)" })
    }

    @Test func renameSettingsSurviveMissingKeys() throws {
        var state = PersistedState()
        state.rename.template = "X###"
        state.convert.rename = true
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["renameTemplates"] = nil
        var convert = try #require(json["convert"] as? [String: Any])
        convert["renameStartNumber"] = nil
        json["convert"] = convert
        var rename = try #require(json["rename"] as? [String: Any])
        rename["startNumber"] = nil
        json["rename"] = rename
        let restored = PersistedState.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(restored.rename.template == "X###")
        #expect(restored.rename.startNumber == 1)
        #expect(restored.convert.rename == true)
        #expect(restored.convert.renameStartNumber == 1)
        #expect(restored.renameTemplates == StandardSizes.renameTemplates)
    }
}

@Suite(.serialized)
struct RenameFlowTests {
    @Test func applyAndUndo() throws {
        let ws = try Workspace()
        let app = AppModel()
        app.add(ws.images)
        app.state.rename.template = "Praia_#"
        let entries = BatchRename.plan(app.inputs.map(\.url), settings: app.state.rename, dates: BatchConverter.fileDate)
        app.applyRename(entries)
        let dir = ws.images[0].deletingLastPathComponent()
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Praia_1.jpg").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Praia_2.jpg").path))
        #expect(app.inputs.allSatisfy { $0.url.lastPathComponent.hasPrefix("Praia_") })
        #expect(app.lastRename.count == 2)
        app.undoLastRename()
        #expect(fm.fileExists(atPath: ws.images[0].path))
        #expect(fm.fileExists(atPath: ws.images[1].path))
        #expect(Set(app.inputs.map(\.url)) == Set(ws.images))
        #expect(app.lastRename.isEmpty)
    }

    @Test func partialUndoKeepsTheRestOfTheHistory() throws {
        let ws = try Workspace()
        let app = AppModel()
        app.add(ws.images)
        app.state.rename.template = "Praia_#"
        app.applyRename(BatchRename.plan(app.inputs.map(\.url), settings: app.state.rename, dates: BatchConverter.fileDate))
        #expect(app.lastRename.count == 2)

        // A rename that changes nothing keeps the previous undo.
        app.applyRename(BatchRename.plan(app.inputs.map(\.url), settings: app.state.rename, dates: BatchConverter.fileDate))
        #expect(app.lastRename.count == 2)

        try Data("blocker".utf8).write(to: ws.images[0])
        app.undoLastRename()
        #expect(app.alert != nil)
        #expect(app.lastRename.map(\.from) == [ws.images[0]])
        #expect(FileManager.default.fileExists(atPath: ws.images[1].path))

        app.alert = nil
        try FileManager.default.removeItem(at: ws.images[0])
        app.undoLastRename()
        #expect(app.alert == nil)
        #expect(app.lastRename.isEmpty)
        #expect(Set(app.inputs.map(\.url)) == Set(ws.images))
    }
}


@Suite(.serialized)
struct BackgroundAddTests {
    /// Folder scanning and sort-key reading happen off the main thread, and the result lands once, de-duplicated.
    @Test func addInBackgroundScansDeduplicatesAndSorts() async throws {
        let ws = try Workspace()
        let app = AppModel()
        app.setSort(InputSort(key: .size, descending: true))
        app.addInBackground([ws.root.appendingPathComponent("Fotos")])
        app.addInBackground([ws.images[0]]) // already inside the folder being scanned
        for _ in 0..<200 where app.inputs.count < 2 || app.isScanning { try await Task.sleep(for: .milliseconds(25)) }
        #expect(app.inputs.count == 2)
        #expect(!app.isScanning)
        let sizes = app.inputs.map { BatchConverter.fileSize($0.url) }
        #expect(sizes == sizes.sorted(by: >))
        try await Task.sleep(for: .milliseconds(200))
        #expect(app.totalBytes == sizes.reduce(0, +))
    }

    @Test func undoRestoresRemovedFiles() throws {
        let ws = try Workspace()
        let app = AppModel()
        app.add(ws.images)
        let before = app.inputs
        app.remove(Set(before.map(\.url)))
        #expect(app.inputs.isEmpty)
        app.restore(before)
        #expect(app.inputs == before)
    }
}

struct PreviewInfoTests {
    @Test func readsFixtureMetadata() throws {
        let ws = try Workspace()
        let info = PreviewInfo.load(ws.images[0])
        #expect(info.size != nil)
        #expect(info.size == ImageLoader.pixelSize(ws.images[0]))
        #expect(info.bytes == BatchConverter.fileSize(ws.images[0]))
        #expect(info.bytes > 0)
    }

    @Test func missingFile() {
        let info = PreviewInfo.load(URL(fileURLWithPath: "/nonexistent/x.jpg"))
        #expect(info.size == nil)
        #expect(info.bytes == 0)
    }
}

struct BatchNumbersTests {
    @Test func ratioAndSavings() {
        #expect(BatchNumbers(old: 1000, new: 400).ratioPercent == 40)
        #expect(BatchNumbers(old: 1000, new: 400).saved == 600)
        #expect(BatchNumbers(old: 1000, new: 1500).ratioPercent == 150)
        #expect(BatchNumbers(old: 1000, new: 1500).saved == 0)
        #expect(BatchNumbers(old: 0, new: 0).ratioPercent == 0)
        #expect(BatchNumbers(old: 0, new: 0).saved == 0)
    }
}

struct AdvancedStepToggleTests {
    @Test func onEnablesApply() {
        let s = AdvancedStep.crop.applying(true, to: ConvertSettings())
        #expect(s.advanced.crop.enabled)
        #expect(s.useAdvancedOptions)
    }

    @Test func offKeepsApply() {
        var base = ConvertSettings()
        base.useAdvancedOptions = true
        base.advanced.crop.enabled = true
        let s = AdvancedStep.crop.applying(false, to: base)
        #expect(!s.advanced.crop.enabled)
        #expect(s.useAdvancedOptions)
    }

    @Test func routeIDs() {
        #expect(SheetRoute.advanced(.crop).id == "advanced-crop")
        #expect(SheetRoute.advanced(nil).id == "advanced")
    }
}
