import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import HyperImageCore

/// Opt-in: compares our output with the original app's reference renders.
/// REF_OUTPUT_DIR=<FSResizer-spec/ref-output> [REF_SAVE_DIR=<dir>] swift test --filter ReferenceComparison
struct ReferenceComparison {
    static let cases: [(String, @Sendable (inout AdvancedOptions) -> Void)] = [
        ("resize-px-800x600", { $0.resize.enabled = true }),
        ("resize-px-800x800-noaspect", { $0.resize.enabled = true; $0.resize.height = 800; $0.resize.width = 800; $0.resize.preserveAspectRatio = false }),
        ("resize-px-800x800-smartcrop", { $0.resize.enabled = true; $0.resize.height = 800; $0.resize.width = 800; $0.resize.smartCropping = true }),
        ("resize-px-800x800-smartfill", { $0.resize.enabled = true; $0.resize.height = 800; $0.resize.width = 800; $0.resize.smartFilling = true }),
        ("resize-pct-25", { $0.resize.enabled = true; $0.resize.mode = .percentage; $0.resize.percentage = 25 }),
        ("resize-oneside-width-500", { $0.resize.enabled = true; $0.resize.mode = .oneSide; $0.resize.sideLength = 500 }),
        ("rotate-90", { $0.rotate.enabled = true; $0.rotate.rotate = true }),
        ("rotate-180", { $0.rotate.enabled = true; $0.rotate.rotate = true; $0.rotate.angle = .halfTurn }),
        ("flip-h", { $0.rotate.enabled = true; $0.rotate.flipHorizontal = true }),
        ("flip-v", { $0.rotate.enabled = true; $0.rotate.flipVertical = true }),
        ("crop-px-640x480-center", { $0.crop.enabled = true }),
        ("crop-px-xy-100-50", { $0.crop.enabled = true; $0.crop.useOrigin = true; $0.crop.originX = 100; $0.crop.originY = 50 }),
        ("crop-ratio-4x3", { $0.crop.enabled = true; $0.crop.mode = .aspectRatio }),
        ("canvas-px-1400x1000", { $0.canvas.enabled = true; $0.canvas.width = 1400; $0.canvas.height = 1000 }),
        ("canvas-expand-10pct", { $0.canvas.enabled = true; $0.canvas.mode = .expand }),
        ("colordepth-16", { $0.colorDepth.enabled = true; $0.colorDepth.depth = .bits4 }),
        ("colordepth-2", { $0.colorDepth.enabled = true; $0.colorDepth.depth = .bits1 }),
        ("adj-brightness-80", { $0.adjustments.enabled = true; $0.adjustments.brightness = 80 }),
        ("adj-contrast-50", { $0.adjustments.enabled = true; $0.adjustments.contrast = 50 }),
        ("adj-gamma-2", { $0.adjustments.enabled = true; $0.adjustments.gamma = 2 }),
        ("adj-hue-90", { $0.adjustments.enabled = true; $0.adjustments.hue = 90 }),
        ("adj-saturation-m100", { $0.adjustments.enabled = true; $0.adjustments.saturation = -100 }),
        ("adj-lightness-50", { $0.adjustments.enabled = true; $0.adjustments.lightness = 50 }),
        ("adj-red-100", { $0.adjustments.enabled = true; $0.adjustments.red = 100 }),
        ("adj-sharpen-100", { $0.adjustments.enabled = true; $0.adjustments.sharpen = 100 }),
        ("adj-grayscale", { $0.adjustments.enabled = true; $0.adjustments.grayscale = true }),
        ("adj-negative", { $0.adjustments.enabled = true; $0.adjustments.negative = true }),
        ("adj-sepia", { $0.adjustments.enabled = true; $0.adjustments.sepia = true }),
        ("border-default", { $0.border.enabled = true }),
        ("border-all-frames", { $0.border.enabled = true; $0.border.frame2.enabled = true; $0.border.frame3.enabled = true; $0.border.innerFrame.enabled = true }),
        ("text-default", { $0.text.enabled = true }),
        ("text-background-round", { o in
            o.text.enabled = true; o.text.background = true; o.text.roundedBackground = true
        }),
    ]

    @Test func compareWithReference() throws {
        guard let refDir = ProcessInfo.processInfo.environment["REF_OUTPUT_DIR"] else { return }
        let save = ProcessInfo.processInfo.environment["REF_SAVE_DIR"].map { URL(fileURLWithPath: $0) }
        var lines: [String] = []
        for (name, configure) in Self.cases {
            var options = AdvancedOptions()
            configure(&options)
            let pipeline = try ImagePipeline(options: options)
            for input in ["paisagem", "retrato"] {
                let ref = URL(fileURLWithPath: refDir).appendingPathComponent(name).appendingPathComponent("\(input).jpg")
                guard let refImage = try? ImageLoader.load(ref).image else { continue }
                // The reference inputs carry the file dates the original stamped with $H1.
                let refInput = URL(fileURLWithPath: refDir).deletingLastPathComponent().appendingPathComponent("ref-input/\(input).jpg")
                let source = FileManager.default.fileExists(atPath: refInput.path) ? refInput : Fixtures.url(input)
                let ours = try pipeline.process(try ImageLoader.load(source)).image
                let diff = Self.meanDifference(ours, refImage)
                lines.append(String(format: "%-30@ %-9@ ours %4dx%-4d ref %4dx%-4d  diff %@", name as NSString, input as NSString,
                                    ours.width, ours.height, refImage.width, refImage.height,
                                    diff.map { String(format: "%5.1f", $0) } ?? "  n/a"))
                if let save {
                    try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
                    let data = try ImageEncoder.encode(.init(image: ours, sourceProperties: .empty, sourceJPEGQuality: nil, dpiX: 72, dpiY: 72),
                                                       format: .png, settings: FormatSettings())
                    try data.write(to: save.appendingPathComponent("\(name)__\(input).png"))
                }
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// Mean absolute RGB difference (0–255) when sizes match.
    static func meanDifference(_ a: CGImage, _ b: CGImage) -> Double? {
        guard a.width == b.width, a.height == b.height else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let pa = try? Bitmap(image: a, colorSpace: space).pixels, let pb = try? Bitmap(image: b, colorSpace: space).pixels else { return nil }
        var total = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            total += abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
        }
        return Double(total) / Double(pa.count / 4 * 3)
    }
}
