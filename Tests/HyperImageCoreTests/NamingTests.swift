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

struct TextVariableTests {
    let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                              year: 2026, month: 10, day: 18, hour: 14, minute: 56, second: 3).date!

    func context(_ metadata: ImageMetadata = ImageMetadata()) -> TextVariableContext {
        TextVariableContext(fileURL: URL(fileURLWithPath: "/fotos/viagem/praia.jpg"), fileDate: date,
                            imageSize: PixelSize(width: 800, height: 600), metadata: metadata)
    }

    @Test func dateFallsBackToFileDateWithoutExif() {
        #expect(TextVariables.expand("$H1", context: context()) == "2026-10-18  14:56")
    }

    @Test func sizeAndNames() {
        #expect(TextVariables.expand("$Ax$B $C1 $C2 $C3", context: context()) == "800x600 praia.jpg praia /fotos/viagem")
    }

    @Test func longestTokenWins() {
        var m = ImageMetadata()
        m.software = "SW"
        m.latitude = -23.5
        m.longitude = -46.25
        #expect(TextVariables.expand("$G|$GPS1", context: context(m)) == "SW|-23.500000, -46.250000")
    }

    @Test func dateParts() {
        #expect(TextVariables.expand("$D2/$D3/$D4 $D5:$D6:$D7", context: context()) == "2026/10/18 14:56:03")
    }

    @Test func unknownDollarIsKept() {
        #expect(TextVariables.expand("US$ 5 $Z", context: context()) == "US$ 5 $Z")
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

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("hyperimage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
