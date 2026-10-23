import Foundation
import Testing
@testable import HyperImageCore

struct RenameTemplateTests {
    let url = URL(fileURLWithPath: "/tmp/ABC/John.jpg")
    let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                              year: 2004, month: 9, day: 30, hour: 8, minute: 5, second: 9).date!

    @Test(arguments: [
        ("Image#####", "Image00032"),
        ("$P_#####", "ABC_00032"),
        ("$Y-$M-$D_#####", "2004-09-30_00032"),
        ("$Y-$M-$D_$H$N$S", "2004-09-30_080509"),
        ("*_tn", "John_tn"),
        ("##-*-#", "32-John-32"),
        ("a/b:c", "a-b-c"),
    ])
    func officialExamples(template: String, expected: String) {
        #expect(RenameTemplate.render(template, originalURL: url, number: 32, date: date) == expected)
    }

    @Test func sequenceDetection() {
        #expect(RenameTemplate.usesSequence("Image###"))
        #expect(!RenameTemplate.usesSequence("*_tn"))
    }

    @Test func searchReplace() {
        var rule = SearchReplaceRule()
        rule.pairs[0] = .init(search: "IMG", replace: "Foto")
        rule.pairs[1] = .init(search: "_", replace: " ")
        rule.extensionPair = .init(search: "jpeg", replace: "jpg")
        #expect(rule.apply(name: "img_0001", ext: "JPEG") == ("Foto 0001", "jpg"))
        rule.caseSensitive = true
        #expect(rule.apply(name: "img_0001", ext: "JPEG") == ("img 0001", "JPEG"))
    }

    @Test func extensionCase() {
        #expect(ExtensionCase.upper.apply("jpg") == "JPG")
        #expect(ExtensionCase.lower.apply("JpG") == "jpg")
        #expect(ExtensionCase.noChange.apply("JpG") == "JpG")
    }
}

struct BatchRenameTests {
    @Test func swapsNamesWithoutLosingFiles() throws {
        let dir = try TemporaryDirectory()
        let a = dir.url.appendingPathComponent("a.txt"), b = dir.url.appendingPathComponent("b.txt")
        try Data("A".utf8).write(to: a)
        try Data("B".utf8).write(to: b)
        var settings = BatchRenameSettings()
        settings.method = .searchReplace
        settings.searchReplace.pairs[0] = .init(search: "a", replace: "c")
        let entries = BatchRename.plan([a, b], settings: settings, dates: { _ in Date() })
        #expect(entries.map(\.destination.lastPathComponent) == ["c.txt", "b.txt"])
        let outcome = BatchRename.execute(entries)
        #expect(outcome.renamed == 1)
        #expect(try String(contentsOf: dir.url.appendingPathComponent("c.txt"), encoding: .utf8) == "A")
    }

    @Test func flagsDuplicateDestinations() throws {
        let dir = try TemporaryDirectory()
        let files = try ["x1.txt", "x2.txt"].map { name -> URL in
            let u = dir.url.appendingPathComponent(name)
            try Data().write(to: u)
            return u
        }
        var settings = BatchRenameSettings()
        settings.template = "same"
        let entries = BatchRename.plan(files, settings: settings, dates: { _ in Date() })
        #expect(entries.allSatisfy { $0.conflict })
        let outcome = BatchRename.execute(entries)
        #expect(outcome.renamed == 0)
    }

    @Test func templateNumbersFromStart() throws {
        let dir = try TemporaryDirectory()
        let files = try ["b.jpg", "a.jpg"].map { name -> URL in
            let u = dir.url.appendingPathComponent(name)
            try Data().write(to: u)
            return u
        }
        var settings = BatchRenameSettings()
        settings.template = "Img###"
        settings.startNumber = 7
        settings.extensionCase = .upper
        let entries = BatchRename.plan(files, settings: settings, dates: { _ in Date() })
        #expect(entries.map(\.destination.lastPathComponent) == ["Img007.JPG", "Img008.JPG"])
    }
}

struct RenameUndoTests {
    private func makeFiles(_ dir: TemporaryDirectory) throws -> [URL] {
        try ["a.txt", "b.txt"].map { name in
            let u = dir.url.appendingPathComponent(name)
            try Data(name.utf8).write(to: u)
            return u
        }
    }

    private func renamed(_ files: [URL]) -> RenameOutcome {
        var settings = BatchRenameSettings()
        settings.template = "N#"
        let entries = BatchRename.plan(files, settings: settings, dates: { _ in Date() })
        return BatchRename.execute(entries)
    }

    @Test func undoRestoresOriginalNames() throws {
        let dir = try TemporaryDirectory()
        let files = try makeFiles(dir)
        let outcome = renamed(files)
        #expect(outcome.moved.count == 2)
        let undo = BatchRename.execute(BatchRename.undoPlan(outcome.moved))
        #expect(undo.renamed == 2)
        #expect(try String(contentsOf: files[0], encoding: .utf8) == "a.txt")
        #expect(try String(contentsOf: files[1], encoding: .utf8) == "b.txt")
    }

    @Test func undoSkipsTakenName() throws {
        let dir = try TemporaryDirectory()
        let files = try makeFiles(dir)
        let outcome = renamed(files)
        try Data("new".utf8).write(to: files[0])
        let plan = BatchRename.undoPlan(outcome.moved)
        #expect(plan[0].conflict)
        _ = BatchRename.execute(plan)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.url.appendingPathComponent("N1.txt").path))
        #expect(try String(contentsOf: files[0], encoding: .utf8) == "new")
    }
}
