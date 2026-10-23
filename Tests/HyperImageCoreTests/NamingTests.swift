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

    @Test func dateDetection() {
        #expect(RenameTemplate.usesDate("$Y-$M-$D_###"))
        #expect(RenameTemplate.usesDate("x$s"))
        #expect(!RenameTemplate.usesDate("Image#####"))
        #expect(!RenameTemplate.usesDate("$P_*"))
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

    @Test func extensionReplacementCannotAddSeparators() {
        var rule = SearchReplaceRule()
        rule.extensionPair = .init(search: "jpg", replace: "x/y:z")
        #expect(rule.apply(name: "a", ext: "jpg") == ("a", "x-y-z"))
    }

    @Test func fileNameValidity() {
        #expect(RenameTemplate.isValidFileName("a.jpg"))
        #expect(!RenameTemplate.isValidFileName(""))
        #expect(!RenameTemplate.isValidFileName("."))
        #expect(!RenameTemplate.isValidFileName(".."))
        #expect(RenameTemplate.isValidFileName(String(repeating: "é", count: 127)))
        #expect(!RenameTemplate.isValidFileName(String(repeating: "é", count: 128)))
    }

    @Test func extensionCase() {
        #expect(ExtensionCase.upper.apply("jpg") == "JPG")
        #expect(ExtensionCase.lower.apply("JpG") == "jpg")
        #expect(ExtensionCase.noChange.apply("JpG") == "JpG")
    }
}

struct BatchRenameTests {
    @Test func renamesOneOfTwoFiles() throws {
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

    @Test func flagsNamesTooLong() throws {
        let dir = try TemporaryDirectory()
        let file = dir.url.appendingPathComponent("a.jpg")
        try Data().write(to: file)
        var settings = BatchRenameSettings()
        settings.template = String(repeating: "*", count: 300)
        let entries = BatchRename.plan([file], settings: settings, dates: { _ in Date() })
        #expect(entries.map(\.conflict) == [true])
        #expect(BatchRename.execute(entries).renamed == 0)
        #expect(FileManager.default.fileExists(atPath: file.path))
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

/// Regression tests for CR-01: renames onto a name that stays put, real swaps, case-only renames.
struct BatchRenameSafetyTests {
    private func write(_ dir: TemporaryDirectory, _ files: [(String, String)]) throws -> [URL] {
        try files.map { name, content in
            let u = dir.url.appendingPathComponent(name)
            try Data(content.utf8).write(to: u)
            return u
        }
    }

    private func contents(_ dir: TemporaryDirectory) throws -> [String: String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        return try Dictionary(uniqueKeysWithValues: names.map { name in
            (name, try String(contentsOf: dir.url.appendingPathComponent(name), encoding: .utf8))
        })
    }

    @Test func chainOntoConflictIsFlaggedAndLosesNothing() throws {
        let dir = try TemporaryDirectory()
        let listed = try write(dir, [("photo.jpg", "PHOTO"), ("IMG_0001.jpg", "ONE"), ("IMG_0002.jpg", "TWO")])
        _ = try write(dir, [("IMG_0003.jpg", "THREE")])
        var settings = BatchRenameSettings()
        settings.template = "IMG_####"
        let entries = BatchRename.plan(listed, settings: settings, dates: { _ in Date() })
        #expect(entries.map(\.destination.lastPathComponent) == ["IMG_0001.jpg", "IMG_0002.jpg", "IMG_0003.jpg"])
        #expect(entries.map(\.conflict) == [true, true, true])
        #expect(BatchRename.counts(entries) == (changes: 0, conflicts: 3))
        let outcome = BatchRename.execute(entries)
        #expect(outcome.renamed == 0)
        #expect(outcome.failures.isEmpty)
        #expect(try contents(dir) == ["photo.jpg": "PHOTO", "IMG_0001.jpg": "ONE", "IMG_0002.jpg": "TWO", "IMG_0003.jpg": "THREE"])
    }

    @Test func swapsTwoNames() throws {
        let dir = try TemporaryDirectory()
        let files = try write(dir, [("a.txt", "A"), ("b.txt", "B")])
        var settings = BatchRenameSettings()
        settings.method = .searchReplace
        settings.searchReplace.pairs = [.init(search: "a", replace: "x"), .init(search: "b", replace: "a"), .init(search: "x", replace: "b")]
        let entries = BatchRename.plan(files, settings: settings, dates: { _ in Date() })
        #expect(entries.map(\.destination.lastPathComponent) == ["b.txt", "a.txt"])
        #expect(!entries.contains { $0.conflict })
        let outcome = BatchRename.execute(entries)
        #expect(outcome.renamed == 2)
        #expect(try contents(dir) == ["a.txt": "B", "b.txt": "A"])
        let undo = BatchRename.execute(BatchRename.undoPlan(outcome.moved))
        #expect(undo.renamed == 2)
        #expect(try contents(dir) == ["a.txt": "A", "b.txt": "B"])
    }

    @Test func caseOnlyRename() throws {
        let dir = try TemporaryDirectory()
        let files = try write(dir, [("a.JPG", "A")])
        var settings = BatchRenameSettings()
        settings.template = "*"
        settings.extensionCase = .lower
        let entries = BatchRename.plan(files, settings: settings, dates: { _ in Date() })
        #expect(entries.map(\.conflict) == [false])
        let outcome = BatchRename.execute(entries)
        #expect(outcome.renamed == 1)
        #expect(try contents(dir) == ["a.jpg": "A"])
        let undo = BatchRename.execute(BatchRename.undoPlan(outcome.moved))
        #expect(undo.renamed == 1)
        #expect(try contents(dir) == ["a.JPG": "A"])
    }

    @Test func undoChainOntoTakenNameIsFlagged() throws {
        let dir = try TemporaryDirectory()
        let url = { (name: String) in dir.url.appendingPathComponent(name) }
        // State after the forward rename IMG_0002→IMG_0001, IMG_0003→IMG_0002, photo→IMG_0003…
        _ = try write(dir, [("IMG_0001.jpg", "TWO"), ("IMG_0002.jpg", "THREE"), ("IMG_0003.jpg", "PHOTO")])
        let moves = [
            RenameMove(from: url("IMG_0002.jpg"), to: url("IMG_0001.jpg")),
            RenameMove(from: url("IMG_0003.jpg"), to: url("IMG_0002.jpg")),
            RenameMove(from: url("photo.jpg"), to: url("IMG_0003.jpg")),
        ]
        // …then the user creates a new photo.jpg.
        _ = try write(dir, [("photo.jpg", "NEW")])
        let plan = BatchRename.undoPlan(moves)
        #expect(plan.map(\.conflict) == [true, true, true])
        let outcome = BatchRename.execute(plan)
        #expect(outcome.renamed == 0)
        #expect(try contents(dir) == ["IMG_0001.jpg": "TWO", "IMG_0002.jpg": "THREE", "IMG_0003.jpg": "PHOTO", "photo.jpg": "NEW"])
    }

    @Test func failedRollbackLeavesAVisibleFileAndRecordsIt() throws {
        let dir = try TemporaryDirectory()
        let url = { (name: String) in dir.url.appendingPathComponent(name) }
        _ = try write(dir, [("photo.jpg", "PHOTO"), ("IMG_0001.jpg", "ONE"), ("IMG_0002.jpg", "TWO")])
        // Hand-made plan (bypassing `plan`) so phase 2 fails and the old name is already taken.
        let entries = [
            RenameEntry(number: 1, source: url("photo.jpg"), destination: url("IMG_0001.jpg"), conflict: false),
            RenameEntry(number: 2, source: url("IMG_0001.jpg"), destination: url("IMG_0002.jpg"), conflict: false),
        ]
        let outcome = BatchRename.execute(entries)
        #expect(outcome.renamed == 1)
        #expect(outcome.failures.count == 1)
        let rescued = url("IMG_0001 (HyperImage 1).jpg")
        #expect(outcome.moved.last == RenameMove(from: url("IMG_0001.jpg"), to: rescued))
        #expect(try contents(dir) == ["IMG_0001.jpg": "PHOTO", "IMG_0001 (HyperImage 1).jpg": "ONE", "IMG_0002.jpg": "TWO"])
    }
}
