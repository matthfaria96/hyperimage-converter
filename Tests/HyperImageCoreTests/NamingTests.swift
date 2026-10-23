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



    @Test func fileNameValidity() {
        #expect(RenameTemplate.isValidFileName("a.jpg"))
        #expect(!RenameTemplate.isValidFileName(""))
        #expect(!RenameTemplate.isValidFileName("."))
        #expect(!RenameTemplate.isValidFileName(".."))
        #expect(RenameTemplate.isValidFileName(String(repeating: "é", count: 127)))
        #expect(!RenameTemplate.isValidFileName(String(repeating: "é", count: 128)))
    }

}
