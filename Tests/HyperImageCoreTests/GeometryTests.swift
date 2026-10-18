import CoreGraphics
import Testing
@testable import HyperImageCore

/// Expected sizes come from the reference outputs of the original app (SPEC §8).
struct ResizeGeometryTests {
    let landscape = PixelSize(width: 1200, height: 800)
    let portrait = PixelSize(width: 600, height: 900)

    func pixels(_ w: Int, _ h: Int, configure: (inout ResizeOptions) -> Void = { _ in }) -> ResizeOptions {
        var o = ResizeOptions()
        o.enabled = true
        o.width = w
        o.height = h
        configure(&o)
        return o
    }

    @Test func fitsInsideBoxWhenPreservingAspect() {
        #expect(ResizeGeometry.plan(source: landscape, options: pixels(800, 600), sourceDPI: 72)?.canvas == PixelSize(width: 800, height: 533))
        #expect(ResizeGeometry.plan(source: portrait, options: pixels(800, 600), sourceDPI: 72)?.canvas == PixelSize(width: 400, height: 600))
    }

    @Test func stretchesWithoutAspect() {
        let o = pixels(800, 800) { $0.preserveAspectRatio = false }
        #expect(ResizeGeometry.plan(source: landscape, options: o, sourceDPI: 72)?.canvas == PixelSize(width: 800, height: 800))
    }

    @Test func smartCropFillsAndOverflows() throws {
        let plan = try #require(ResizeGeometry.plan(source: landscape, options: pixels(800, 800) { $0.smartCropping = true }, sourceDPI: 72))
        #expect(plan.canvas == PixelSize(width: 800, height: 800))
        #expect(plan.imageRect == CGRect(x: -200, y: 0, width: 1200, height: 800))
    }

    @Test func smartFillLetterboxes() throws {
        let plan = try #require(ResizeGeometry.plan(source: landscape, options: pixels(800, 800) { $0.smartFilling = true }, sourceDPI: 72))
        #expect(plan.canvas == PixelSize(width: 800, height: 800))
        #expect(plan.imageRect == CGRect(x: 0, y: 133, width: 800, height: 533))
        #expect(plan.needsFill)
    }

    @Test func percentage() {
        var o = ResizeOptions()
        o.mode = .percentage
        o.percentage = 25
        #expect(ResizeGeometry.plan(source: landscape, options: o, sourceDPI: 72)?.canvas == PixelSize(width: 300, height: 200))
        #expect(ResizeGeometry.plan(source: portrait, options: o, sourceDPI: 72)?.canvas == PixelSize(width: 150, height: 225))
    }

    @Test(arguments: [
        (ResizeSide.width, 500, PixelSize(width: 500, height: 333), PixelSize(width: 500, height: 750)),
        (ResizeSide.longSide, 600, PixelSize(width: 600, height: 400), PixelSize(width: 400, height: 600)),
        (ResizeSide.shortSide, 400, PixelSize(width: 600, height: 400), PixelSize(width: 400, height: 600)),
    ])
    func oneSide(side: ResizeSide, length: Int, expectedLandscape: PixelSize, expectedPortrait: PixelSize) {
        var o = ResizeOptions()
        o.mode = .oneSide
        o.side = side
        o.sideLength = length
        #expect(ResizeGeometry.plan(source: landscape, options: o, sourceDPI: 72)?.canvas == expectedLandscape)
        #expect(ResizeGeometry.plan(source: portrait, options: o, sourceDPI: 72)?.canvas == expectedPortrait)
    }

    @Test func printSize() {
        var o = ResizeOptions()
        o.mode = .printSize
        o.printWidth = 2
        o.printHeight = 2
        o.printDPI = 100
        #expect(ResizeGeometry.plan(source: landscape, options: o, sourceDPI: 72)?.canvas == PixelSize(width: 200, height: 133))
        o.printUnit = .centimeter
        o.printWidth = 2.54
        o.printHeight = 2.54
        #expect(ResizeGeometry.plan(source: landscape, options: o, sourceDPI: 72)?.canvas == PixelSize(width: 100, height: 67))
    }

    @Test func switchMatchesLongSides() {
        let o = pixels(800, 600) { $0.switchToMatchLongSides = true }
        // 800×600 becomes a 600×800 box for a portrait source.
        #expect(ResizeGeometry.plan(source: portrait, options: o, sourceDPI: 72)?.canvas == PixelSize(width: 533, height: 800))
    }

    @Test func onlyIfLargerSkipsSmallImages() {
        let o = pixels(4000, 4000) { $0.onlyIfLarger = true }
        #expect(ResizeGeometry.plan(source: landscape, options: o, sourceDPI: 72) == nil)
        var pct = ResizeOptions()
        pct.mode = .percentage
        pct.percentage = 200
        pct.onlyIfLarger = true
        #expect(ResizeGeometry.plan(source: landscape, options: pct, sourceDPI: 72) == nil)
    }
}

struct CropAndCanvasGeometryTests {
    let landscape = PixelSize(width: 1200, height: 800)
    let portrait = PixelSize(width: 600, height: 900)

    @Test func centredCropSwitchesForPortrait() {
        let o = CropOptions()
        #expect(CropGeometry.rect(source: landscape, options: o, sourceDPI: 72) == PixelRect(x: 280, y: 160, width: 640, height: 480))
        #expect(CropGeometry.rect(source: portrait, options: o, sourceDPI: 72) == PixelRect(x: 60, y: 130, width: 480, height: 640))
    }

    @Test func cropFromOrigin() {
        var o = CropOptions()
        o.useOrigin = true
        o.originX = 100
        o.originY = 50
        #expect(CropGeometry.rect(source: landscape, options: o, sourceDPI: 72) == PixelRect(x: 100, y: 50, width: 640, height: 480))
        o.originX = 5000
        #expect(CropGeometry.rect(source: landscape, options: o, sourceDPI: 72).x == 560)
    }

    @Test func cropToAspectRatio() {
        var o = CropOptions()
        o.mode = .aspectRatio
        #expect(CropGeometry.rect(source: landscape, options: o, sourceDPI: 72).size == PixelSize(width: 1067, height: 800))
        #expect(CropGeometry.rect(source: portrait, options: o, sourceDPI: 72).size == PixelSize(width: 600, height: 800))
    }

    @Test func cropLargerThanImageIsClamped() {
        var o = CropOptions()
        o.width = 5000
        o.height = 5000
        #expect(CropGeometry.rect(source: landscape, options: o, sourceDPI: 72) == PixelRect(x: 0, y: 0, width: 1200, height: 800))
    }

    @Test func canvasPixelsCentres() {
        var o = CanvasOptions()
        o.width = 1400
        o.height = 1000
        let plan = CanvasGeometry.plan(source: landscape, options: o)
        #expect(plan.size == PixelSize(width: 1400, height: 1000))
        #expect(plan.imageOrigin == (100, 100))
    }

    @Test func canvasExpandPercentBothSides() {
        var o = CanvasOptions()
        o.mode = .expand
        #expect(CanvasGeometry.plan(source: landscape, options: o).size == PixelSize(width: 1440, height: 960))
        #expect(CanvasGeometry.plan(source: portrait, options: o).size == PixelSize(width: 720, height: 1080))
        #expect(CanvasGeometry.plan(source: landscape, options: o).imageOrigin == (120, 80))
    }

    @Test func canvasExpandOneSidePixels() {
        var o = CanvasOptions()
        o.mode = .expand
        o.expandUnit = .pixels
        o.expandHorizontal = 50
        o.expandVertical = 0
        o.horizontalSide = .left
        let plan = CanvasGeometry.plan(source: landscape, options: o)
        #expect(plan.size == PixelSize(width: 1250, height: 800))
        #expect(plan.imageOrigin == (50, 0))
    }

    @Test func borderLayoutMatchesReference() {
        let defaults = BorderOptions()
        #expect(BorderEffect.layout(for: landscape, options: defaults).canvas == PixelSize(width: 1241, height: 841))
        #expect(BorderEffect.layout(for: portrait, options: defaults).canvas == PixelSize(width: 641, height: 941))
        var all = defaults
        all.frame2.enabled = true
        all.frame3.enabled = true
        all.innerFrame.enabled = true
        #expect(BorderEffect.layout(for: landscape, options: all).canvas == PixelSize(width: 1247, height: 847))
    }

    @Test func overlayAnchors() {
        let box = CGSize(width: 100, height: 20), canvas = CGSize(width: 1000, height: 500)
        #expect(overlayOrigin(size: box, in: canvas, position: .bottomRight, offsetX: 10, offsetY: 10) == CGPoint(x: 890, y: 470))
        #expect(overlayOrigin(size: box, in: canvas, position: .center, offsetX: 10, offsetY: 10) == CGPoint(x: 450, y: 240))
        #expect(overlayOrigin(size: box, in: canvas, position: .topLeft, offsetX: 5, offsetY: 7) == CGPoint(x: 5, y: 7))
    }
}
