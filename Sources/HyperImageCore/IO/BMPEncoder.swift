import Foundation

/// Writes palette BMPs (1 bit for 2 colours, 4 for ≤16, else 8), bottom-up, uncompressed.
enum BMPEncoder {
    static func encode(_ image: IndexedImage, dpiX: Double, dpiY: Double) -> Data {
        let bitsPerPixel = image.palette.count <= 2 ? 1 : image.palette.count <= 16 ? 4 : 8
        let paletteCount = 1 << bitsPerPixel
        let rowBytes = ((image.width * bitsPerPixel + 31) / 32) * 4
        let pixelOffset = 14 + 40 + paletteCount * 4
        let fileSize = pixelOffset + rowBytes * image.height

        var out = Data(capacity: fileSize)
        func u16(_ v: Int) { out.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func u32(_ v: Int) { out.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) }) }
        func pixelsPerMeter(_ dpi: Double) -> Int { Int((dpi / 0.0254).rounded()) }

        out.append(contentsOf: [0x42, 0x4D]) // "BM"
        u32(fileSize); u32(0); u32(pixelOffset)
        u32(40); u32(image.width); u32(image.height); u16(1); u16(bitsPerPixel); u32(0)
        u32(rowBytes * image.height); u32(pixelsPerMeter(dpiX)); u32(pixelsPerMeter(dpiY))
        u32(image.palette.count); u32(0)
        for i in 0..<paletteCount {
            let c = i < image.palette.count ? image.palette[i] : IndexedImage.Entry(r: 0, g: 0, b: 0)
            out.append(contentsOf: [c.b, c.g, c.r, 0])
        }
        var row = [UInt8](repeating: 0, count: rowBytes)
        for y in stride(from: image.height - 1, through: 0, by: -1) {
            for i in row.indices { row[i] = 0 }
            let base = y * image.width
            for x in 0..<image.width {
                let index = image.indices[base + x]
                switch bitsPerPixel {
                case 8: row[x] = index
                case 4: row[x / 2] |= x % 2 == 0 ? index << 4 : index & 0x0F
                default: row[x / 8] |= (index & 1) << UInt8(7 - x % 8)
                }
            }
            out.append(contentsOf: row)
        }
        return out
    }
}
