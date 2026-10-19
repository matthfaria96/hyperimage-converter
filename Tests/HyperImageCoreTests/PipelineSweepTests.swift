import CoreGraphics
import Foundation
import Testing
@testable import HyperImageCore

/// Extreme-but-valid advanced options on tiny and normal images must never throw or produce an empty image.
struct PipelineSweepTests {
    static func loaded(_ w: Int, _ h: Int) throws -> LoadedImage {
        let image = try SweepImages.make(w, h)
        return LoadedImage(url: URL(fileURLWithPath: "/tmp/x.png"), image: image, properties: ImageProperties(raw: [:]),
                           metadata: ImageMetadata(), sourceType: "public.png", fileSize: 0, modificationDate: Date(), creationDate: nil)
    }

    static var cases: [(String, (inout AdvancedOptions) -> Void)] {
        var c: [(String, (inout AdvancedOptions) -> Void)] = []
        for mode in ResizeMode.allCases { for side in ResizeSide.allCases { for filter in ResizeFilter.allCases {
            c.append(("resize \(mode) \(side) \(filter)", { o in
                o.resize.enabled = true; o.resize.mode = mode; o.resize.side = side; o.resize.filter = filter
                o.resize.percentage = 0.5; o.resize.width = 1; o.resize.height = 1; o.resize.sideLength = 1
                o.resize.printWidth = 0.001; o.resize.printHeight = 0.001; o.resize.printDPI = 1
            }))
        } } }
        for flags in [(true, false), (false, true), (true, true)] {
            c.append(("resize smart \(flags)", { o in
                o.resize.enabled = true; o.resize.width = 5000; o.resize.height = 3; o.resize.smartCropping = flags.0; o.resize.smartFilling = flags.1
                o.resize.preserveAspectRatio = true; o.resize.switchToMatchLongSides = true
            }))
        }
        for angle in RotationAngle.allCases { c.append(("rotate \(angle)", { o in o.rotate = RotateOptions(); o.rotate.enabled = true; o.rotate.rotate = true; o.rotate.angle = angle; o.rotate.flipHorizontal = true })) }
        for mode in CropMode.allCases {
            c.append(("crop \(mode) huge+origin", { o in
                o.crop.enabled = true; o.crop.mode = mode; o.crop.width = 99999; o.crop.height = 1; o.crop.useOrigin = true
                o.crop.originX = 99999; o.crop.originY = -5; o.crop.ratioWidth = 1000; o.crop.ratioHeight = 0.01
                o.crop.printWidth = 100; o.crop.printHeight = 0.0001
            }))
        }
        for mode in CanvasMode.allCases { for unit in CanvasExpandUnit.allCases {
            c.append(("canvas \(mode) \(unit) shrink", { o in
                o.canvas.enabled = true; o.canvas.mode = mode; o.canvas.expandUnit = unit; o.canvas.width = 1; o.canvas.height = 1
                o.canvas.percentWidth = 1; o.canvas.percentHeight = 1; o.canvas.expandHorizontal = -500; o.canvas.expandVertical = -500
                o.canvas.switchForPortrait = true; o.canvas.horizontalSide = .left; o.canvas.verticalSide = .bottom
            }))
        } }
        for depth in ColorDepth.allCases { c.append(("depth \(depth)", { o in o.colorDepth.enabled = true; o.colorDepth.depth = depth })) }
        c.append(("adjust extremes", { o in
            o.adjustments.enabled = true; o.adjustments.brightness = 255; o.adjustments.contrast = -100; o.adjustments.gamma = 0
            o.adjustments.hue = 180; o.adjustments.saturation = -100; o.adjustments.lightness = 100; o.adjustments.red = -255
            o.adjustments.shadows = 100; o.adjustments.highlights = -100; o.adjustments.sharpen = 100; o.adjustments.unsharpMask = true
            o.adjustments.unsharpRadius = 0; o.adjustments.sepia = true; o.adjustments.negative = true; o.adjustments.beforeResize = true
        }))
        c.append(("adjust soften", { o in o.adjustments.enabled = true; o.adjustments.sharpen = -100; o.adjustments.gamma = 10; o.adjustments.unsharpMask = true; o.adjustments.unsharpRadius = 50 }))
        for pos in OverlayPosition.allCases {
            c.append(("text \(pos)", { o in
                o.text.enabled = true; o.text.position = pos; o.text.text = "Olá $B $GPS2 😀\nlinha"; o.text.fontSize = 0
                o.text.offsetX = -9999; o.text.offsetY = 9999; o.text.background = true; o.text.roundedBackground = true
                o.text.fontFamily = "FonteQueNaoExiste"; o.text.opacity = 0
            }))
        }
        c.append(("text empty", { o in o.text.enabled = true; o.text.text = "" }))
        c.append(("border huge", { o in
            o.border.enabled = true; o.border.frame1.width = 0; o.border.frame2 = FrameLine(enabled: true, width: 500, color: .black)
            o.border.innerFrame.enabled = true; o.border.innerFrame.distance = 9999; o.border.innerFrame.width = 50
            o.border.shadow.radius = 200; o.border.shadow.depth = 200
        }))
        c.append(("border negative", { o in o.border.enabled = true; o.border.frame1.width = -10; o.border.shadow.radius = -3; o.border.shadow.depth = -3 }))
        c.append(("dpi tiny", { o in o.dpi.enabled = true; o.dpi.x = 0.001; o.dpi.y = 1_000_000 }))
        return c
    }

    @Test func extremeOptionsNeverFail() throws {
        var failures: [String] = []
        for (w, h) in [(1, 1), (3, 2), (2, 9), (320, 200)] {
            let source = try Self.loaded(w, h)
            for (name, configure) in Self.cases {
                var o = AdvancedOptions(); configure(&o)
                guard o.validationError() == nil else { continue }
                do {
                    let out = try ImagePipeline(options: o).process(source).image
                    if out.width < 1 || out.height < 1 || out.width > 20000 || out.height > 20000 {
                        failures.append("\(w)x\(h) \(name): \(out.width)x\(out.height)")
                    }
                } catch {
                    failures.append("\(w)x\(h) \(name): \(error)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) falhas:\n\(failures.joined(separator: "\n"))")
    }
}

enum SweepImages {
    static func make(_ w: Int, _ h: Int) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return try #require(ctx.makeImage())
    }
}
