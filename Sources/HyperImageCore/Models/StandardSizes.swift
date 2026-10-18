/// A width × height pair offered by the "standard size" pickers.
public struct PixelSize: Codable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width) × \(height)" }
}

public enum StandardSizes {
    public static let resize: [PixelSize] = [
        (400, 300), (640, 480), (720, 480), (800, 600), (1024, 768), (1200, 900), (1280, 720), (1366, 768),
        (1600, 1200), (1920, 1080), (2048, 1536), (2560, 1440), (3200, 1800), (3840, 2160),
    ].map { PixelSize(width: $0.0, height: $0.1) }

    public static let cropAndCanvas: [PixelSize] = [
        (120, 90), (160, 120), (200, 150), (320, 240), (400, 300), (640, 480), (800, 600), (1024, 600),
        (1024, 768), (1200, 900), (1280, 800), (1280, 1024), (1366, 768), (1440, 900), (1600, 1200),
        (1920, 1080), (2048, 1536), (2272, 1704),
    ].map { PixelSize(width: $0.0, height: $0.1) }

    public static let percentages: [Double] = [25, 50, 150, 200, 250, 300, 400, 500]

    public static let sideLengths = [100, 120, 160, 200, 320, 400, 480, 600, 640, 768, 800, 900, 1024, 1200, 1280, 1600, 2000]

    public static let printDPIs: [Double] = [72, 96, 120, 200, 300, 600]

    public static let renameTemplates = ["Image#####", "$P_#####", "$Y-$M-$D_#####", "$Y-$M-$D_$H$N$S", "*_tn"]
}
