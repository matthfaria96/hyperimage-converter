import UniformTypeIdentifiers

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case jpeg, bmp, gif, png, jpeg2000, tiff, pdf, webp, heic, avif

    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .bmp: "BMP"
        case .gif: "GIF"
        case .png: "PNG"
        case .jpeg2000: "JPEG 2000"
        case .tiff: "TIFF"
        case .pdf: "PDF"
        case .webp: "WebP"
        case .heic: "HEIC"
        case .avif: "AVIF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .jpeg2000: "jp2"
        case .tiff: "tif"
        default: rawValue
        }
    }

    public var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .bmp: .bmp
        case .gif: .gif
        case .png: .png
        case .jpeg2000: UTType("public.jpeg-2000")!
        case .tiff: .tiff
        case .pdf: .pdf
        case .webp: .webP
        case .heic: .heic
        case .avif: UTType("public.avif")!
        }
    }
}

public enum JPEGPhotometric: String, Codable, CaseIterable, Sendable {
    case noChange, rgb, grayscale, ycbcr, cmyk
}

/// Chroma subsampling: none is 4:4:4, medium 4:2:2, high 4:2:0 (the original's default).
public enum JPEGSubsampling: String, Codable, CaseIterable, Sendable {
    case none, medium, high
}

public struct JPEGSettings: Codable, Equatable, Sendable {
    public static let smoothingRange = 0...100

    public var quality = 90
    public var useOriginalQuality = false
    public var photometric = JPEGPhotometric.noChange
    public var subsampling = JPEGSubsampling.high
    public var smoothing = 0
    public var optimizeHuffman = true
    public var progressive = false
    public var keepMetadata = true

    public init() {}

    /// Missing keys keep their defaults, so options saved before a field existed still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = JPEGSettings()
        quality = try c.decodeIfPresent(Int.self, forKey: .quality) ?? d.quality
        useOriginalQuality = try c.decodeIfPresent(Bool.self, forKey: .useOriginalQuality) ?? d.useOriginalQuality
        photometric = try c.decodeIfPresent(JPEGPhotometric.self, forKey: .photometric) ?? d.photometric
        subsampling = try c.decodeIfPresent(JPEGSubsampling.self, forKey: .subsampling) ?? d.subsampling
        smoothing = try c.decodeIfPresent(Int.self, forKey: .smoothing) ?? d.smoothing
        optimizeHuffman = try c.decodeIfPresent(Bool.self, forKey: .optimizeHuffman) ?? d.optimizeHuffman
        progressive = try c.decodeIfPresent(Bool.self, forKey: .progressive) ?? d.progressive
        keepMetadata = try c.decodeIfPresent(Bool.self, forKey: .keepMetadata) ?? d.keepMetadata
    }
}

/// Palette sizes offered by the indexed formats; `nil` means true colour.
public enum PaletteSize: Int, Codable, CaseIterable, Sendable {
    case trueColor = 0, c256 = 256, c128 = 128, c64 = 64, c32 = 32, c16 = 16, c8 = 8, c4 = 4, blackWhite = 2

    public var colorCount: Int? { self == .trueColor ? nil : rawValue }
}

public struct BMPSettings: Codable, Equatable, Sendable {
    public static let allowedColors: [PaletteSize] = [.trueColor, .c256, .c16, .blackWhite]
    public var colors = PaletteSize.trueColor
}

public struct GIFSettings: Codable, Equatable, Sendable {
    public var colors = PaletteSize.c256
    /// Keeps transparent pixels transparent; otherwise they are flattened onto white.
    public var transparent = false
}

/// PNG row filter. The original offers None/Sub/Paeth; adaptive lets ImageIO pick per row (its default).
public enum PNGFilter: String, Codable, CaseIterable, Sendable {
    case adaptive, none, sub, paeth

    /// IMAGEIO_PNG_FILTER_* bits for kCGImagePropertyPNGCompressionFilter.
    var imageIOValue: Int {
        switch self {
        case .adaptive: 0x08 | 0x10 | 0x20 | 0x40 | 0x80
        case .none: 0x08
        case .sub: 0x10
        case .paeth: 0x80
        }
    }
}

public struct PNGSettings: Codable, Equatable, Sendable {
    /// Only true colour, 256 colours and black & white are offered for PNG.
    public static let allowedColors: [PaletteSize] = [.trueColor, .c256, .blackWhite]
    public var colors = PaletteSize.trueColor
    public var interlaced = false
    public var filter = PNGFilter.adaptive

    public init() {}

    /// Missing keys keep their defaults, so settings saved before a field existed still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = try c.decodeIfPresent(PaletteSize.self, forKey: .colors) ?? .trueColor
        interlaced = try c.decodeIfPresent(Bool.self, forKey: .interlaced) ?? false
        filter = try c.decodeIfPresent(PNGFilter.self, forKey: .filter) ?? .adaptive
    }
}

public enum JPEG2000Photometric: String, Codable, CaseIterable, Sendable {
    case rgb, grayscale
}

public struct JPEG2000Settings: Codable, Equatable, Sendable {
    /// 0...100; 100 is lossless.
    public var quality = 80
    public var photometric = JPEG2000Photometric.rgb
}

public enum TIFFCompression: String, Codable, CaseIterable, Sendable {
    case none, lzw, zip, jpeg, packBits, g3Fax1D, g3Fax2D, g4Fax

    var tagValue: Int {
        switch self {
        case .none: 1
        case .g3Fax1D, .g3Fax2D: 3 // ImageIO writes one-dimensional G3 for both
        case .g4Fax: 4
        case .lzw: 5
        case .jpeg: 7
        case .zip: 8
        case .packBits: 32773
        }
    }

    /// CCITT fax schemes only store black & white, so the image is reduced to 1 bit first.
    public var isFax: Bool { self == .g3Fax1D || self == .g3Fax2D || self == .g4Fax }
}

public enum TIFFPhotometric: String, Codable, CaseIterable, Sendable {
    case noChange, rgb, palette256, cmyk, grayscale
}

public struct TIFFSettings: Codable, Equatable, Sendable {
    public var compression = TIFFCompression.lzw
    public var photometric = TIFFPhotometric.noChange
}

public enum PDFQuality: Int, Codable, CaseIterable, Sendable {
    case lossless = 100, q95 = 95, q90 = 90, q85 = 85, q80 = 80, q75 = 75, q70 = 70, q50 = 50, blackWhite = 0
}

public struct PDFSettings: Codable, Equatable, Sendable {
    public var quality = PDFQuality.q90
    /// When false the page is sized at 72 dpi (screen); when true the original file's DPI is used.
    public var useOriginalDPI = true
}

public struct WebPSettings: Codable, Equatable, Sendable {
    public var lossless = false
    public var quality = 90
    public var sharpYUV = true
}

public struct HEIFSettings: Codable, Equatable, Sendable {
    public var quality = 80
    public var keepMetadata = true
}

public struct FormatSettings: Codable, Equatable, Sendable {
    public var jpeg = JPEGSettings()
    public var bmp = BMPSettings()
    public var gif = GIFSettings()
    public var png = PNGSettings()
    public var jpeg2000 = JPEG2000Settings()
    public var tiff = TIFFSettings()
    public var pdf = PDFSettings()
    public var webp = WebPSettings()
    public var heic = HEIFSettings()
    public var avif = HEIFSettings(quality: 70)

    public init() {}

    /// Restores the defaults of one format, leaving the others untouched.
    public func resetting(_ format: OutputFormat) -> FormatSettings {
        var copy = self
        let fresh = FormatSettings()
        switch format {
        case .jpeg: copy.jpeg = fresh.jpeg
        case .bmp: copy.bmp = fresh.bmp
        case .gif: copy.gif = fresh.gif
        case .png: copy.png = fresh.png
        case .jpeg2000: copy.jpeg2000 = fresh.jpeg2000
        case .tiff: copy.tiff = fresh.tiff
        case .pdf: copy.pdf = fresh.pdf
        case .webp: copy.webp = fresh.webp
        case .heic: copy.heic = fresh.heic
        case .avif: copy.avif = fresh.avif
        }
        return copy
    }
}
