import Foundation

/// Palette-reduced image: one palette index per pixel.
public struct IndexedImage: Sendable {
    public struct Entry: Hashable, Sendable {
        public var r: UInt8, g: UInt8, b: UInt8
    }

    public let width: Int
    public let height: Int
    public let palette: [Entry]
    public let indices: [UInt8]
    /// Palette slot reserved for fully transparent pixels, if any.
    public let transparentIndex: Int?
}

/// Median-cut colour reduction without dithering (matches the reference: 2 colours = plain threshold).
public enum Quantizer {
    public static func quantize(_ bitmap: Bitmap, colors requested: Int, keepTransparency: Bool = false) -> IndexedImage {
        let colors = max(2, min(256, requested))
        let hasAlpha = keepTransparency && !bitmap.isOpaque
        let pixels = straightRGB(bitmap)
        if colors == 2 && !hasAlpha { return threshold(bitmap, rgb: pixels) }

        let slots = hasAlpha ? colors - 1 : colors
        let palette = medianCut(pixels, alpha: bitmap.pixels, count: slots)
        var lookup = NearestLookup(palette: palette)
        let transparent = hasAlpha ? palette.count : nil
        var indices = [UInt8](repeating: 0, count: bitmap.width * bitmap.height)
        for i in 0..<indices.count {
            if let transparent, bitmap.pixels[i * 4 + 3] < 128 {
                indices[i] = UInt8(transparent)
            } else {
                indices[i] = lookup.index(pixels[i * 3], pixels[i * 3 + 1], pixels[i * 3 + 2])
            }
        }
        let finalPalette = hasAlpha ? palette + [IndexedImage.Entry(r: 0, g: 0, b: 0)] : palette
        return IndexedImage(width: bitmap.width, height: bitmap.height, palette: finalPalette, indices: indices, transparentIndex: transparent)
    }

    /// Re-expands an indexed image to RGBA (used by the Color Depth step).
    public static func expand(_ indexed: IndexedImage, like bitmap: Bitmap) -> Bitmap {
        var out = [UInt8](repeating: 0, count: indexed.indices.count * 4)
        for (i, index) in indexed.indices.enumerated() {
            // With a transparent slot (GIF) alpha is binary: every other pixel is fully opaque.
            let alpha: UInt8 = indexed.transparentIndex == nil ? bitmap.pixels[i * 4 + 3] : 255
            if Int(index) == indexed.transparentIndex { continue }
            let entry = indexed.palette[Int(index)]
            out[i * 4] = premultiply(entry.r, alpha)
            out[i * 4 + 1] = premultiply(entry.g, alpha)
            out[i * 4 + 2] = premultiply(entry.b, alpha)
            out[i * 4 + 3] = alpha
        }
        return Bitmap(width: bitmap.width, height: bitmap.height, pixels: out, colorSpace: bitmap.colorSpace)
    }

    private static func premultiply(_ c: UInt8, _ a: UInt8) -> UInt8 {
        UInt8((Int(c) * Int(a) + 127) / 255)
    }

    private static func straightRGB(_ bitmap: Bitmap) -> [UInt8] {
        var rgb = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 3)
        bitmap.pixels.withUnsafeBufferPointer { p in
            for i in 0..<(bitmap.width * bitmap.height) {
                let a = Int(p[i * 4 + 3])
                for c in 0..<3 {
                    let v = Int(p[i * 4 + c])
                    rgb[i * 3 + c] = a == 0 ? 0 : UInt8(min(255, (v * 255 + a / 2) / a))
                }
            }
        }
        return rgb
    }

    private static func threshold(_ bitmap: Bitmap, rgb: [UInt8]) -> IndexedImage {
        let indices = (0..<(bitmap.width * bitmap.height)).map { i -> UInt8 in
            let luma = 0.299 * Double(rgb[i * 3]) + 0.587 * Double(rgb[i * 3 + 1]) + 0.114 * Double(rgb[i * 3 + 2])
            return luma >= 128 ? 1 : 0
        }
        return IndexedImage(width: bitmap.width, height: bitmap.height,
                            palette: [.init(r: 0, g: 0, b: 0), .init(r: 255, g: 255, b: 255)],
                            indices: indices, transparentIndex: nil)
    }

    private static func medianCut(_ rgb: [UInt8], alpha: [UInt8], count: Int) -> [IndexedImage.Entry] {
        let total = rgb.count / 3
        let step = max(1, total / 120_000)
        var samples: [SIMD3<Int32>] = []
        samples.reserveCapacity(total / step + 1)
        for i in Swift.stride(from: 0, to: total, by: step) where alpha[i * 4 + 3] >= 128 {
            samples.append(SIMD3(Int32(rgb[i * 3]), Int32(rgb[i * 3 + 1]), Int32(rgb[i * 3 + 2])))
        }
        if samples.isEmpty { return [IndexedImage.Entry(r: 0, g: 0, b: 0)] }

        var boxes: [ArraySlice<SIMD3<Int32>>] = [samples[...]]
        while boxes.count < count {
            guard let (index, axis) = widestBox(boxes) else { break }
            let sorted = boxes[index].sorted { $0[axis] < $1[axis] }
            let mid = sorted.count / 2
            boxes.remove(at: index)
            boxes.append(sorted[..<mid])
            boxes.append(sorted[mid...])
        }
        return boxes.map { box in
            let sum = box.reduce(SIMD3<Int32>(0, 0, 0), &+)
            let n = Int32(box.count)
            return IndexedImage.Entry(r: UInt8(sum.x / n), g: UInt8(sum.y / n), b: UInt8(sum.z / n))
        }
    }

    private static func widestBox(_ boxes: [ArraySlice<SIMD3<Int32>>]) -> (Int, Int)? {
        var best: (index: Int, axis: Int, range: Int32)?
        for (i, box) in boxes.enumerated() where box.count > 1 {
            var lo = SIMD3<Int32>(repeating: 255), hi = SIMD3<Int32>(repeating: 0)
            for p in box {
                lo = pointwiseMin(lo, p)
                hi = pointwiseMax(hi, p)
            }
            let range = hi &- lo
            let axis = range.x >= range.y && range.x >= range.z ? 0 : (range.y >= range.z ? 1 : 2)
            if range[axis] > 0, range[axis] > (best?.range ?? -1) {
                best = (i, axis, range[axis])
            }
        }
        return best.map { ($0.index, $0.axis) }
    }
}

/// Nearest-palette lookup cached on a 5-bit-per-channel grid.
private struct NearestLookup {
    let palette: [IndexedImage.Entry]
    private var cache: [Int16]

    init(palette: [IndexedImage.Entry]) {
        self.palette = palette
        self.cache = [Int16](repeating: -1, count: 32 * 32 * 32)
    }

    mutating func index(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt8 {
        let key = (Int(r) >> 3) << 10 | (Int(g) >> 3) << 5 | Int(b) >> 3
        if cache[key] >= 0 { return UInt8(cache[key]) }
        let found = search(r, g, b)
        cache[key] = Int16(found)
        return found
    }

    private func search(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt8 {
        var best = 0, bestDistance = Int.max
        for (i, e) in palette.enumerated() {
            let dr = Int(e.r) - Int(r), dg = Int(e.g) - Int(g), db = Int(e.b) - Int(b)
            let d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
            if d < bestDistance { bestDistance = d; best = i }
        }
        return UInt8(best)
    }
}
