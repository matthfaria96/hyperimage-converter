import Foundation
import Testing
@testable import HyperImageCore

struct HostileOptionsTests {
    @Test func doubleToIntRejectsNonFiniteAndHuge() {
        #expect(DelphiValue.double(.nan).int == nil)
        #expect(DelphiValue.double(.infinity).int == nil)
        #expect(DelphiValue.double(-.infinity).int == nil)
        #expect(DelphiValue.double(1e300).int == nil)
        #expect(DelphiValue.double(9_007_199_254_740_992).int == nil)
        #expect(DelphiValue.double(1234.6).int == 1235)
    }

    @Test func infiniteExtendedIsIgnored() throws {
        var b = CCFImportTests.Builder()
        b.bool("UseResize", true)
        b.name("resizeWidth"); b.bytes += [5, 0, 0, 0, 0, 0, 0, 0, 0x80, 0xFF, 0x7F]
        let o = try CCFImporter.importOptions(b.data)
        #expect(o.resize.width == ResizeOptions().width)
    }

    @Test func hugeCCFDimensionsAreClamped() throws {
        var b = CCFImportTests.Builder()
        b.bool("UseResize", true)
        // 1_000_000 as an x87 extended: 2^19 * 1.9073486328125
        b.name("resizeWidth"); b.bytes += [5] + extended(1_000_000)
        b.name("CropW"); b.bytes += [5] + extended(1_000_000)
        b.name("canvasW"); b.bytes += [5] + extended(1_000_000)
        b.name("BasedSize"); b.bytes += [5] + extended(1_000_000)
        b.name("F1W"); b.bytes += [5] + extended(1_000_000)
        let o = try CCFImporter.importOptions(b.data)
        #expect(o.resize.width == SafeLimits.maxSide)
        #expect(o.resize.sideLength == SafeLimits.maxSide)
        #expect(o.crop.width == SafeLimits.maxSide)
        #expect(o.canvas.width == SafeLimits.maxSide)
        #expect(o.border.frame1.width == SafeLimits.maxSide)
    }

    @Test func hugeJSONNumberNeverTraps() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hostile-\(UUID()).hyperoptions")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"resize":{"width":1e300}}"#.utf8).write(to: url)
        let o = try? AdvancedOptions.load(from: url)
        if let o { #expect(o.resize.width == ResizeOptions().width) }
    }

    /// Encodes a positive integer-valued double as a little-endian x87 extended.
    private func extended(_ v: Int) -> [UInt8] {
        let exponent = Int.bitWidth - 1 - v.leadingZeroBitCount
        let mantissa = UInt64(v) << UInt64(63 - exponent)
        let biased = UInt16(exponent + 16383)
        return withUnsafeBytes(of: mantissa.littleEndian, Array.init) + withUnsafeBytes(of: biased.littleEndian, Array.init)
    }
}
