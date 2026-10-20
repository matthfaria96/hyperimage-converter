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

    @Test func validationRejectsOversizedDimensions() {
        func resize(_ w: Int, _ h: Int) -> String? {
            var o = AdvancedOptions(); o.resize.enabled = true; o.resize.mode = .pixels
            o.resize.width = w; o.resize.height = h
            return o.validationError()
        }
        #expect(resize(30_001, 10) != nil)
        #expect(resize(30_000, 10_000) == nil)
        #expect(resize(25_000, 20_000) != nil)

        var side = AdvancedOptions(); side.resize.enabled = true; side.resize.mode = .oneSide; side.resize.sideLength = 40_000
        #expect(side.validationError() != nil)
        var crop = AdvancedOptions(); crop.crop.enabled = true; crop.crop.mode = .pixels; crop.crop.width = 50_000
        #expect(crop.validationError() != nil)
        var canvas = AdvancedOptions(); canvas.canvas.enabled = true; canvas.canvas.mode = .pixels; canvas.canvas.width = 31_000
        #expect(canvas.validationError() != nil)
        var border = AdvancedOptions(); border.border.enabled = true; border.border.frame1.width = 30_001
        #expect(border.validationError() != nil)
        var inner = AdvancedOptions(); inner.border.enabled = true; inner.border.innerFrame.enabled = true
        inner.border.innerFrame.distance = 30_001
        #expect(inner.validationError() != nil)
        #expect(AdvancedOptions().validationError() == nil)
    }

    @Test func borderValidationSurvivesIntMin() {
        var o = AdvancedOptions(); o.border.enabled = true; o.border.frame1.width = Int.min
        #expect(o.validationError() != nil)
        var shadow = AdvancedOptions(); shadow.border.enabled = true; shadow.border.shadow.depth = Int.min
        #expect(shadow.validationError() != nil)
    }

    @Test func bitmapByteCountIsChecked() throws {
        #expect(try Bitmap.checkedByteCount(width: 100, height: 100) == 40_000)
        #expect(throws: ImagingError.self) { try Bitmap.checkedByteCount(width: Int.max / 2, height: 4) }
        #expect(throws: ImagingError.self) { try Bitmap.checkedByteCount(width: 30_000, height: 30_000) }
        #expect(throws: ImagingError.self) { try Bitmap.checkedByteCount(width: 0, height: 10) }
    }

    /// Encodes a positive integer-valued double as a little-endian x87 extended.
    private func extended(_ v: Int) -> [UInt8] {
        let exponent = Int.bitWidth - 1 - v.leadingZeroBitCount
        let mantissa = UInt64(v) << UInt64(63 - exponent)
        let biased = UInt16(exponent + 16383)
        return withUnsafeBytes(of: mantissa.littleEndian, Array.init) + withUnsafeBytes(of: biased.littleEndian, Array.init)
    }
}
