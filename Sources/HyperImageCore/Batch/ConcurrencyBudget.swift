import Foundation
import ImageIO

/// Decides how many images a batch may decode at once, from source pixel counts and physical memory.
public enum ConcurrencyBudget {
    /// RGBA, 8 bits per channel.
    public static let bytesPerPixel = 4
    /// Decoded source, working copy, resized/encoded buffers held by one worker.
    public static let copiesPerWorker = 4
    /// Share of physical memory the batch may claim for decoded pixels.
    public static let memoryFraction = 0.25
    /// Any source above this runs the whole batch serially.
    public static let hardLimitPixels = 40_000_000

    /// Sized by the largest source, since any worker may end up holding it. Unknown sizes count as small.
    public static func workers(pixelCounts: [Int?], base: Int, physicalMemory: UInt64) -> Int {
        guard base > 1 else { return 1 }
        let known = pixelCounts.compactMap { $0 }
        if known.contains(where: { $0 > hardLimitPixels }) { return 1 }
        let largest = known.max() ?? 0
        guard largest > 0 else { return base }
        let perWorker = Double(largest) * Double(bytesPerPixel * copiesPerWorker)
        let budget = Double(physicalMemory) * memoryFraction
        return min(max(Int(budget / perWorker), 1), base)
    }

    /// Width × height from the image header only (no decode); nil when unreadable.
    public static func pixelCount(of url: URL) -> Int? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let (product, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : product
    }
}
