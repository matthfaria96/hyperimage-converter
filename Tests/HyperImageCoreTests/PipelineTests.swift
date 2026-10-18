import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures")!
    }

    static func landscape() throws -> LoadedImage { try ImageLoader.load(url("paisagem")) }
    static func portrait() throws -> LoadedImage { try ImageLoader.load(url("retrato")) }

    static func rgba(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let bitmap = try Bitmap(image: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let i = (y * bitmap.width + x) * 4
        return Array(bitmap.pixels[i..<(i + 4)])
    }
}

/// Runs the real pipeline on the reference inputs and checks the reference output sizes (SPEC §8).
struct PipelineTests {
    func run(_ configure: (inout AdvancedOptions) -> Void, on loaded: LoadedImage) throws -> ProcessedImage {
        var options = AdvancedOptions()
        configure(&options)
        return try ImagePipeline(options: options).process(loaded)
    }

    @Test func fixturesLoad() throws {
        #expect(try Fixtures.landscape().image.pixelSize == PixelSize(width: 1200, height: 800))
        #expect(try Fixtures.portrait().image.pixelSize == PixelSize(width: 600, height: 900))
    }

    @Test(arguments: ResizeFilter.allCases)
    func everyFilterProducesTargetSize(filter: ResizeFilter) throws {
        let out = try run({ $0.resize.enabled = true; $0.resize.filter = filter }, on: Fixtures.landscape())
        #expect(out.image.pixelSize == PixelSize(width: 800, height: 533))
    }

    @Test func upscaleWorks() throws {
        let out = try run({ $0.resize.enabled = true; $0.resize.mode = .percentage; $0.resize.percentage = 150 }, on: Fixtures.portrait())
        #expect(out.image.pixelSize == PixelSize(width: 900, height: 1350))
    }

    @Test func smartFillPaintsMargins() throws {
        let out = try run({ o in
            o.resize.enabled = true
            o.resize.width = 800
            o.resize.height = 800
            o.resize.smartFilling = true
            o.resize.fillColor = .red
        }, on: Fixtures.landscape())
        #expect(out.image.pixelSize == PixelSize(width: 800, height: 800))
        let corner = try Fixtures.rgba(out.image, x: 2, y: 2)
        #expect(corner[0] > 240 && corner[1] < 15 && corner[2] < 15)
    }

    @Test func rotationIsClockwise() throws {
        let src = try Fixtures.landscape()
        let out = try run({ $0.rotate.enabled = true; $0.rotate.rotate = true; $0.rotate.angle = .clockwise90 }, on: src)
        #expect(out.image.pixelSize == PixelSize(width: 800, height: 1200))
        // Clockwise: the source's top-left corner moves to the top-right.
        let before = try Fixtures.rgba(src.image, x: 3, y: 3)
        let after = try Fixtures.rgba(out.image, x: 800 - 4, y: 3)
        #expect(zip(before, after).allSatisfy { abs(Int($0) - Int($1)) < 6 })
    }

    @Test func flipHorizontalMirrors() throws {
        let src = try Fixtures.landscape()
        let out = try run({ $0.rotate.enabled = true; $0.rotate.flipHorizontal = true }, on: src)
        let before = try Fixtures.rgba(src.image, x: 1150, y: 40)
        let after = try Fixtures.rgba(out.image, x: 49, y: 40)
        #expect(zip(before, after).allSatisfy { abs(Int($0) - Int($1)) < 6 })
    }

    @Test func cropAndCanvas() throws {
        let cropped = try run({ $0.crop.enabled = true }, on: Fixtures.portrait())
        #expect(cropped.image.pixelSize == PixelSize(width: 480, height: 640))
        let canvas = try run({ $0.canvas.enabled = true; $0.canvas.mode = .expand }, on: Fixtures.landscape())
        #expect(canvas.image.pixelSize == PixelSize(width: 1440, height: 960))
        #expect(try Fixtures.rgba(canvas.image, x: 5, y: 5) == [255, 255, 255, 255])
    }

    @Test func twoColorDepthIsPureBlackAndWhite() throws {
        let out = try run({ $0.colorDepth.enabled = true; $0.colorDepth.depth = .bits1 }, on: Fixtures.landscape())
        let bitmap = try Bitmap(image: out.image, colorSpace: out.image.workingColorSpace)
        let values = Set(stride(from: 0, to: bitmap.pixels.count, by: 4).map { bitmap.pixels[$0] })
        #expect(values.isSubset(of: [0, 255]))
    }

    @Test func sixteenColorsAtMost() throws {
        let out = try run({ $0.colorDepth.enabled = true; $0.colorDepth.depth = .bits4 }, on: Fixtures.landscape())
        let bitmap = try Bitmap(image: out.image, colorSpace: out.image.workingColorSpace)
        let colors = Set(stride(from: 0, to: bitmap.pixels.count, by: 4).map {
            UInt32(bitmap.pixels[$0]) << 16 | UInt32(bitmap.pixels[$0 + 1]) << 8 | UInt32(bitmap.pixels[$0 + 2])
        })
        #expect(colors.count <= 16)
    }

    @Test func adjustmentsChangePixels() throws {
        let src = try Fixtures.landscape()
        let negative = try run({ $0.adjustments.enabled = true; $0.adjustments.negative = true }, on: src)
        let a = try Fixtures.rgba(src.image, x: 600, y: 400), b = try Fixtures.rgba(negative.image, x: 600, y: 400)
        #expect(abs(Int(a[0]) + Int(b[0]) - 255) < 4)

        let gray = try run({ $0.adjustments.enabled = true; $0.adjustments.grayscale = true }, on: src)
        let g = try Fixtures.rgba(gray.image, x: 1150, y: 40)
        #expect(abs(Int(g[0]) - Int(g[1])) < 3 && abs(Int(g[1]) - Int(g[2])) < 3)

        let light = try run({ $0.adjustments.enabled = true; $0.adjustments.lightness = 50 }, on: src)
        #expect(try Fixtures.rgba(light.image, x: 600, y: 400)[0] >= 127)
    }

    @Test func borderGrowsImage() throws {
        let out = try run({ $0.border.enabled = true }, on: Fixtures.landscape())
        #expect(out.image.pixelSize == PixelSize(width: 1241, height: 841))
        #expect(try Fixtures.rgba(out.image, x: 15, y: 400)[0] == 255)  // inside the white frame
    }

    @Test func textChangesBottomRightOnly() throws {
        let src = try Fixtures.landscape()
        let out = try run({ $0.text.enabled = true; $0.text.text = "HELLO WORLD"; $0.text.color = .red; $0.text.shadow = false }, on: src)
        let bitmap = try Bitmap(image: out.image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let original = try Bitmap(image: src.image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        func changed(_ region: Range<Int>, _ rows: Range<Int>) -> Bool {
            rows.contains { y in region.contains { x in
                let i = (y * 1200 + x) * 4
                return abs(Int(bitmap.pixels[i]) - Int(original.pixels[i])) > 30
            } }
        }
        #expect(changed(900..<1190, 750..<790))
        #expect(!changed(0..<300, 0..<300))
    }

    @Test func dpiStepOnlyChangesMetadata() throws {
        let out = try run({ $0.dpi.enabled = true; $0.dpi.x = 150; $0.dpi.y = 150 }, on: Fixtures.landscape())
        #expect(out.image.pixelSize == PixelSize(width: 1200, height: 800))
        #expect(out.dpiX == 150)
    }

    @Test func missingWatermarkIsReported() {
        var options = AdvancedOptions()
        options.watermark.enabled = true
        options.watermark.imagePath = "/nonexistent/logo.png"
        #expect(throws: ImagingError.self) { try ImagePipeline(options: options) }
    }

    @Test func validation() {
        var options = AdvancedOptions()
        options.resize.enabled = true
        options.resize.width = 0
        #expect(options.validationError() != nil)
        options.resize.width = 10
        #expect(options.validationError() == nil)
    }

    @Test func optionsRoundTripThroughFile() throws {
        var options = AdvancedOptions()
        options.text.enabled = true
        options.text.text = "Olá $A"
        options.border.frame2.enabled = true
        let file = try TemporaryDirectory().url.appendingPathComponent("o.hyperoptions")
        try options.save(to: file)
        #expect(try AdvancedOptions.load(from: file) == options)
    }
}
