import Foundation

/// Separable two-pass resampler over premultiplied RGBA8 bitmaps.
public enum Resampler {
    public static func resize(_ source: Bitmap, to size: PixelSize, filter: ResizeFilter) -> Bitmap {
        if size == source.size { return source }
        if filter == .nearest || filter == .none { return nearest(source, to: size) }
        let kernel = ResampleKernel.make(filter)
        let horizontal = contributions(sourceLength: source.width, targetLength: size.width, kernel: kernel)
        let vertical = contributions(sourceLength: source.height, targetLength: size.height, kernel: kernel)
        let intermediate = horizontalPass(source, taps: horizontal, targetWidth: size.width)
        let output = verticalPass(intermediate, width: size.width, sourceHeight: source.height, taps: vertical)
        return Bitmap(width: size.width, height: size.height, pixels: output, colorSpace: source.colorSpace)
    }

    private static func horizontalPass(_ source: Bitmap, taps: [Contribution], targetWidth: Int) -> [Float] {
        let rows = source.height
        var out = [Float](repeating: 0, count: rows * targetWidth * 4)
        source.pixels.withUnsafeBufferPointer { srcBuffer in
            out.withUnsafeMutableBufferPointer { dst in
                // Each iteration writes its own row only.
                nonisolated(unsafe) let src = srcBuffer
                nonisolated(unsafe) let dstBase = dst.baseAddress!
                DispatchQueue.concurrentPerform(iterations: rows) { y in
                    let srcRow = y * source.width * 4
                    let dstRow = dstBase + y * targetWidth * 4
                    for x in 0..<targetWidth {
                        let tap = taps[x]
                        var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                        var p = srcRow + tap.start * 4
                        for w in tap.weights {
                            r += Float(src[p]) * w
                            g += Float(src[p + 1]) * w
                            b += Float(src[p + 2]) * w
                            a += Float(src[p + 3]) * w
                            p += 4
                        }
                        let o = x * 4
                        dstRow[o] = r; dstRow[o + 1] = g; dstRow[o + 2] = b; dstRow[o + 3] = a
                    }
                }
            }
        }
        return out
    }

    private static func verticalPass(_ source: [Float], width: Int, sourceHeight: Int, taps: [Contribution]) -> [UInt8] {
        let stride = width * 4
        var out = [UInt8](repeating: 0, count: taps.count * stride)
        source.withUnsafeBufferPointer { srcBuffer in
            out.withUnsafeMutableBufferPointer { dst in
                nonisolated(unsafe) let src = srcBuffer
                nonisolated(unsafe) let dstBase = dst.baseAddress!
                DispatchQueue.concurrentPerform(iterations: taps.count) { y in
                    let tap = taps[y]
                    let row = dstBase + y * stride
                    for i in Swift.stride(from: 0, to: stride, by: 4) {
                        var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                        var p = tap.start * stride + i
                        for w in tap.weights {
                            r += src[p] * w
                            g += src[p + 1] * w
                            b += src[p + 2] * w
                            a += src[p + 3] * w
                            p += stride
                        }
                        let alpha = clamp(a)
                        row[i] = min(clamp(r), alpha)
                        row[i + 1] = min(clamp(g), alpha)
                        row[i + 2] = min(clamp(b), alpha)
                        row[i + 3] = alpha
                    }
                }
            }
        }
        return out
    }

    private static func nearest(_ source: Bitmap, to size: PixelSize) -> Bitmap {
        var out = [UInt8](repeating: 0, count: size.width * size.height * 4)
        let xs = (0..<size.width).map { min(source.width - 1, Int((Double($0) + 0.5) * Double(source.width) / Double(size.width))) }
        source.pixels.withUnsafeBufferPointer { srcBuffer in
            out.withUnsafeMutableBufferPointer { dst in
                nonisolated(unsafe) let src = srcBuffer
                nonisolated(unsafe) let base = dst.baseAddress!
                DispatchQueue.concurrentPerform(iterations: size.height) { y in
                    let sy = min(source.height - 1, Int((Double(y) + 0.5) * Double(source.height) / Double(size.height)))
                    let row = base + y * size.width * 4
                    for (x, sx) in xs.enumerated() {
                        let s = (sy * source.width + sx) * 4
                        row[x * 4] = src[s]; row[x * 4 + 1] = src[s + 1]; row[x * 4 + 2] = src[s + 2]; row[x * 4 + 3] = src[s + 3]
                    }
                }
            }
        }
        return Bitmap(width: size.width, height: size.height, pixels: out, colorSpace: source.colorSpace)
    }

    @inline(__always)
    private static func clamp(_ v: Float) -> UInt8 {
        UInt8(max(0, min(255, v.rounded())))
    }
}
