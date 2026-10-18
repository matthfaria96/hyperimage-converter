import Foundation

/// Estimates the IJG quality (1...100) a JPEG was saved with, from its luminance quantisation table.
public enum JPEGQualityEstimator {
    static let standardLuminance: [Int] = [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56,
        14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
        49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
    ]

    public static func estimate(url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 256 * 1024) else { return nil }
        return estimate(data: header)
    }

    public static func estimate(data: Data) -> Int? {
        let bytes = [UInt8](data)
        var i = 2
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        while i + 4 < bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if marker == 0xDB, let table = luminanceTable(bytes, start: i + 4, end: min(bytes.count, i + 2 + length)) {
                return quality(for: table)
            }
            if marker == 0xDA { return nil }
            i += 2 + length
        }
        return nil
    }

    private static func luminanceTable(_ bytes: [UInt8], start: Int, end: Int) -> [Int]? {
        var p = start
        while p < end {
            let precision = bytes[p] >> 4, id = bytes[p] & 0x0F
            let size = precision == 0 ? 64 : 128
            guard p + 1 + size <= end else { return nil }
            let values = (0..<64).map { k in precision == 0 ? Int(bytes[p + 1 + k]) : Int(bytes[p + 1 + 2 * k]) << 8 | Int(bytes[p + 2 + 2 * k]) }
            if id == 0 { return values }
            p += 1 + size
        }
        return nil
    }

    /// Picks the quality whose scaled standard table is closest (tables are stored in zig-zag order;
    /// the sum is order-independent, so compare totals).
    static func quality(for table: [Int]) -> Int {
        let target = table.reduce(0, +)
        var best = 75, bestDiff = Int.max
        for q in 1...100 {
            let scale = q < 50 ? 5000 / q : 200 - 2 * q
            let total = standardLuminance.reduce(0) { $0 + min(255, max(1, ($1 * scale + 50) / 100)) }
            let diff = abs(total - target)
            if diff < bestDiff { bestDiff = diff; best = q }
        }
        return best
    }
}
