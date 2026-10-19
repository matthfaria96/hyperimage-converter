import Foundation
import Testing
@testable import HyperImageCore

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

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("hyperimage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
