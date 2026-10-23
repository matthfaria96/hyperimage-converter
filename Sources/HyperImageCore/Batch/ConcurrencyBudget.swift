import Foundation
import ImageIO

/// Decides how many images a batch may decode at once, from the largest planned pixel counts and physical memory.
public enum ConcurrencyBudget {
    /// RGBA, 8 bits per channel: the default when the header does not say otherwise.
    public static let bytesPerPixel = 4
    /// RGBA, 32-bit float per channel: the most ImageIO will hand back for one pixel.
    public static let maxBytesPerPixel = 16
    /// Decoded source, working copy, resized/encoded buffers held by one worker.
    public static let copiesPerWorker = 4
    /// Share of physical memory the batch may claim for decoded pixels.
    public static let memoryFraction = 0.25
    /// Any image (source or planned output) above this runs the whole batch serially.
    public static let hardLimitPixels = 40_000_000

    /// Decoded size of one image: pixel count and bytes per pixel (8-bit RGBA is 4, 16-bit 8, float 16).
    public struct Footprint: Equatable, Sendable {
        public var pixels: Int
        public var bytesPerPixel: Int

        public init(pixels: Int, bytesPerPixel: Int = ConcurrencyBudget.bytesPerPixel) {
            self.pixels = pixels
            self.bytesPerPixel = bytesPerPixel
        }

        var bytes: Double { Double(pixels) * Double(bytesPerPixel) }
    }

    /// 8-bit sources: every pixel weighs `bytesPerPixel`.
    public static func workers(pixelCounts: [Int?], base: Int, physicalMemory: UInt64) -> Int {
        workers(footprints: pixelCounts.map { $0.map { Footprint(pixels: $0) } }, base: base, physicalMemory: physicalMemory)
    }

    /// Sized by the heaviest image, since any worker may end up holding it. Unknown sizes count as small.
    public static func workers(footprints: [Footprint?], base: Int, physicalMemory: UInt64) -> Int {
        guard base > 1 else { return 1 }
        let known = footprints.compactMap { $0 }
        if known.contains(where: { $0.pixels > hardLimitPixels }) { return 1 }
        let heaviest = known.map(\.bytes).max() ?? 0
        guard heaviest > 0 else { return base }
        let perWorker = heaviest * Double(copiesPerWorker)
        let budget = Double(physicalMemory) * memoryFraction
        return min(max(Int(budget / perWorker), 1), base)
    }

    /// Width × height from the image header only (no decode); nil when unreadable.
    public static func pixelCount(of url: URL) -> Int? {
        header(of: url).map { area($0.size) }
    }

    /// What a worker holds for this file once the pipeline runs: the source, or the resized /
    /// canvas-enlarged / bordered image when that is bigger, at the source's decoded bit depth.
    /// Header only; nil when unreadable.
    public static func peakFootprint(of url: URL, options: AdvancedOptions) -> Footprint? {
        header(of: url).map {
            Footprint(pixels: plannedPeakPixels(source: $0.size, sourceDPI: $0.dpi, options: options), bytesPerPixel: $0.bytesPerPixel)
        }
    }

    /// Bytes per decoded RGBA pixel for a header's bits per sample; 16-bit and float sources decode wider than 8-bit.
    static func bytesPerPixel(depth: Int?, isFloat: Bool) -> Int {
        let bits = depth ?? (isFloat ? 32 : 8)
        let bytesPerChannel = max(1, (bits + 7) / 8)
        return min(max(4 * bytesPerChannel, bytesPerPixel), maxBytesPerPixel)
    }

    /// Pixel count of the largest image along the pipeline's size-changing steps (crop only shrinks, so it is ignored).
    public static func plannedPeakPixels(source: PixelSize, sourceDPI: Double, options o: AdvancedOptions) -> Int {
        var size = source
        var peak = area(size)
        if o.resize.enabled, let plan = ResizeGeometry.plan(source: size, options: o.resize, sourceDPI: sourceDPI) {
            size = plan.canvas
            peak = max(peak, area(size))
        }
        if o.canvas.enabled {
            size = CanvasGeometry.plan(source: size, options: o.canvas).size
            peak = max(peak, area(size))
        }
        if o.border.enabled {
            size = BorderEffect.layout(for: size, options: o.border).canvas
            peak = max(peak, area(size))
        }
        return peak
    }

    struct SourceHeader {
        /// Upright size (EXIF orientation applied), as the pipeline sees it.
        let size: PixelSize
        let dpi: Double
        let bytesPerPixel: Int
    }

    static func header(of url: URL) -> SourceHeader? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
        let dpi = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let depth = (props[kCGImagePropertyDepth] as? NSNumber)?.intValue
        let isFloat = (props[kCGImagePropertyIsFloat] as? NSNumber)?.boolValue ?? false
        return SourceHeader(size: size, dpi: dpi > 0 ? dpi : 72, bytesPerPixel: bytesPerPixel(depth: depth, isFloat: isFloat))
    }

    static func area(_ size: PixelSize) -> Int {
        guard size.width > 0, size.height > 0 else { return 0 }
        let (product, overflow) = size.width.multipliedReportingOverflow(by: size.height)
        return overflow ? Int.max : product
    }
}
