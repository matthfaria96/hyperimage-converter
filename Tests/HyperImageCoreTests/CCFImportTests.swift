import Foundation
import Testing
@testable import HyperImageCore

struct CCFImportTests {
    /// Builds a minimal TOptionsInfo stream.
    struct Builder {
        var bytes = Array("TPF0".utf8) + [12] + Array("TOptionsInfo".utf8) + [0]

        mutating func name(_ s: String) { bytes += [UInt8(s.utf8.count)] + Array(s.utf8) }
        mutating func bool(_ key: String, _ v: Bool) { name(key); bytes.append(v ? 9 : 8) }
        mutating func int(_ key: String, _ v: Int) {
            name(key)
            if (-128...127).contains(v) { bytes += [2, UInt8(bitPattern: Int8(v))] }
            else { bytes += [3] + withUnsafeBytes(of: Int16(v).littleEndian, Array.init) }
        }
        mutating func string(_ key: String, _ v: String) { name(key); bytes.append(6); name(v) }
        mutating func ident(_ key: String, _ v: String) { name(key); bytes.append(7); name(v) }
        mutating func color(_ key: String, _ v: Int32) { name(key); bytes += [4] + withUnsafeBytes(of: v.littleEndian, Array.init) }
        mutating func set(_ key: String, _ members: [String]) { name(key); bytes.append(11); members.forEach { name($0) }; bytes.append(0) }
        /// 2.5 as an x87 extended.
        mutating func twoAndHalf(_ key: String) { name(key); bytes += [5, 0, 0, 0, 0, 0, 0, 0, 0xA0, 0x00, 0x40] }
        var data: Data { Data(bytes + [0, 0]) }
    }

    @Test func exampleFileHoldsTheDefaults() throws {
        let url = try #require(Bundle.module.url(forResource: "exemplo-opcoes", withExtension: "ccf", subdirectory: "Fixtures"))
        let o = try CCFImporter.load(from: url)
        var d = AdvancedOptions()
        d.resize.enabled = true // the sample was saved with the Resize tab ticked
        #expect(o.resize == d.resize)
        #expect(o.rotate == d.rotate)
        #expect(o.crop == d.crop)
        #expect(o.canvas == d.canvas)
        #expect(o.colorDepth == d.colorDepth)
        #expect(o.adjustments == d.adjustments)
        #expect(o.border == d.border)
        #expect(o.text.text == "($H1)")
        #expect(o.text.fontFamily == "Verdana" && o.text.bold && !o.text.italic && o.text.fontSize == 28)
        #expect(o.text.backgroundColor == .red && o.text.color == .white && o.text.position == .bottomRight)
        #expect(o.watermark.opacity == 100 && o.watermark.position == .bottomRight)
    }

    @Test func nonDefaultValuesMap() throws {
        var b = Builder()
        b.bool("UseResize", true); b.bool("InPixel", false); b.bool("InPercentage", true); b.int("ResizePercentage", 25)
        b.int("ResizeFilter", 9); b.string("ResizePW", "7,5")
        b.bool("UseRotate", true); b.bool("Rotate", true); b.int("RotateIndex", 180)
        b.bool("UseCrop", true); b.int("CropMethod", 2); b.string("CropRW", "16"); b.string("CropRH", "9")
        b.bool("UseColorDepth", true); b.int("colorDepthIndex", 5)
        b.bool("UseEffects", true); b.int("brightness", -40); b.twoAndHalf("gamma"); b.bool("Sepia", true)
        b.bool("UseText", true); b.string("Text", "Linha 1\r\nLinha 2"); b.int("TextAlign", 2)
        b.set("TextStyle", ["fsItalic"]); b.color("TextColor", 0x00FF8000); b.ident("TextBackgroundColor", "clNavy")
        b.int("TextPosition", 0); b.int("TextTrans", 60)
        b.bool("UseCanvasResize", true); b.bool("canvasExpand", true); b.int("canvasW3", 40); b.int("canvasWAlign", 0)
        let o = try CCFImporter.importOptions(b.data)

        #expect(o.resize.enabled && o.resize.mode == .percentage && o.resize.percentage == 25)
        #expect(o.resize.filter == .mitchell && o.resize.printWidth == 7.5)
        #expect(o.rotate.isEffective && o.rotate.angle == .halfTurn)
        #expect(o.crop.mode == .aspectRatio && o.crop.ratioWidth == 16 && o.crop.ratioHeight == 9)
        #expect(o.colorDepth.enabled && o.colorDepth.depth == .bits4)
        #expect(o.adjustments.brightness == -40 && o.adjustments.gamma == 2.5 && o.adjustments.sepia)
        #expect(o.text.text == "Linha 1\nLinha 2" && o.text.alignment == .center)
        #expect(o.text.italic && !o.text.bold && o.text.position == .topLeft && o.text.opacity == 60)
        #expect(o.text.color == RGBAColor(red: 0, green: 128.0 / 255, blue: 1))
        #expect(o.text.backgroundColor == RGBAColor(red: 0, green: 0, blue: 128.0 / 255))
        #expect(o.canvas.mode == .expand && o.canvas.expandHorizontal == 40 && o.canvas.horizontalSide == .left)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: DelphiStreamError.notAComponentStream) { try CCFImporter.importOptions(Data("{}".utf8)) }
        #expect(throws: DelphiStreamError.truncated) { try CCFImporter.importOptions(Data(Array("TPF0".utf8) + [12])) }
        var b = Builder()
        b.name("Odd"); b.bytes.append(99)
        #expect(throws: DelphiStreamError.unsupportedValue(99)) { try CCFImporter.importOptions(b.data) }
    }
}
