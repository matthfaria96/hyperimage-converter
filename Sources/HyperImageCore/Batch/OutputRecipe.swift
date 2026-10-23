import Foundation
import ImageIO

public enum ConvertMode: String, Codable, CaseIterable, Sendable {
    case convert, compress, upscale

    /// A mode this build no longer has (the old "rename" tab) opens in Converter instead of resetting every setting.
    public init(from decoder: Decoder) throws {
        self = ConvertMode(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .convert
    }
}

extension OutputFormat {
    /// The writable format of a source file, used by Compress mode (nil for formats we can read but not write).
    public static func matching(_ url: URL) -> OutputFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "jpe", "jfif": .jpeg
        case "png": .png
        case "gif": .gif
        case "bmp": .bmp
        case "tif", "tiff": .tiff
        case "webp": .webp
        case "heic", "heif", "hif": .heic
        case "avif": .avif
        case "jp2", "j2k", "jpf", "jpx": .jpeg2000
        default: nil
        }
    }

    public var supportsTransparency: Bool {
        switch self {
        case .png, .webp, .tiff, .gif, .heic, .avif: true
        case .jpeg, .bmp, .jpeg2000, .pdf: false
        }
    }
}

/// Comprimir's three levels; the slider can still pick any quality in between.
public enum CompressionLevel: String, CaseIterable, Sendable {
    case lossless, light, balanced, strong

    public var quality: Int {
        switch self {
        case .lossless: 100
        case .light: 85
        case .balanced: 72
        case .strong: 50
        }
    }

    /// The level whose quality matches exactly, or nil for a custom value.
    public static func matching(_ quality: Int) -> CompressionLevel? { allCases.first { $0.quality == quality } }
}

extension OutputFormat {
    /// Formats with a quality setting (the ones Comprimir can shrink by lowering it).
    public static let lossyFormats: [OutputFormat] = [.jpeg, .webp, .heic, .avif, .jpeg2000]
}

extension FormatSettings {
    /// The 0–100 quality the format's encoder uses, or nil when it is lossless.
    public func quality(for format: OutputFormat) -> Int? {
        switch format {
        case .jpeg: jpeg.quality
        case .webp: webp.lossless ? nil : webp.quality
        case .heic: heic.quality
        case .avif: avif.quality
        case .jpeg2000: jpeg2000.quality
        case .bmp, .gif, .png, .tiff, .pdf: nil
        }
    }

    public func with(quality: Int, for format: OutputFormat) -> FormatSettings {
        let q = min(100, max(1, quality))
        var copy = self
        switch format {
        case .jpeg: copy.jpeg.quality = q; copy.jpeg.useOriginalQuality = false
        case .webp: copy.webp.quality = q
        case .heic: copy.heic.quality = q
        case .avif: copy.avif.quality = q
        case .jpeg2000: copy.jpeg2000.quality = q
        case .bmp, .gif, .png, .tiff, .pdf: break
        }
        return copy
    }
}

extension ConvertSettings {
    public func outputFormat(for url: URL) -> OutputFormat {
        switch mode {
        case .convert: format
        case .compress: OutputFormat.matching(url) ?? .jpeg
        case .upscale: upscale.format.outputFormat
        }
    }

    public var nameSuffix: String {
        // Upscaled files always get a suffix: same-format outputs next to the originals would collide otherwise.
        if mode == .upscale { return "-upscale-\(upscale.scale)x" }
        guard addSuffix else { return "" }
        return mode == .compress ? String(localized: "-comprimido") : String(localized: "-convertido")
    }

    /// Advanced Options when enabled, plus the quick "limit dimensions" resize when it does not clash with them.
    /// Comprimir only compresses: no edits and no resizing.
    public var effectiveAdvancedOptions: AdvancedOptions {
        if mode == .compress { return AdvancedOptions() }
        var options = useAdvancedOptions ? advanced : AdvancedOptions()
        if !keepDimensions, !options.resize.enabled, maxLongSide > 0 {
            options.resize.enabled = true
            options.resize.mode = .oneSide
            options.resize.side = .longSide
            options.resize.sideLength = maxLongSide
            options.resize.onlyIfLarger = true
        }
        return options
    }

    /// Quality used by Converter when the user has not chosen to reduce it: visually lossless.
    public static let fullQualityLevel = 95

    public var effectiveFormatSettings: FormatSettings {
        var settings = formatSettings
        switch mode {
        case .convert where fullQuality:
            settings = settings.with(quality: Self.fullQualityLevel, for: format)
        case .compress:
            settings = OutputFormat.lossyFormats.reduce(settings) { $0.with(quality: compressQuality, for: $1) }
            settings.jpeg.keepMetadata = !stripMetadata
            settings.heic.keepMetadata = !stripMetadata
            settings.avif.keepMetadata = !stripMetadata
            settings.jpeg.optimizeHuffman = true
        default:
            break
        }
        // Compress keeps each file as it was, transparency included.
        let flatten = mode != .compress && !preserveTransparency
        settings.flattenTransparency = flatten
        if flatten { settings.gif.transparent = false }
        return settings
    }

    /// The size target belongs to Comprimir; Converter never lowers the quality behind the user's back.
    public var maxFileSizeBytes: Int? { mode == .compress && limitFileSize && maxFileSizeKB > 0 ? maxFileSizeKB * 1024 : nil }
}

/// Encodes one loaded file with everything the settings ask for, including the file-size target.
public enum OutputEncoder {
    public static func encode(_ loaded: LoadedImage, pipeline: ImagePipeline, settings: ConvertSettings) throws -> EncodedOutput {
        let output = try encodeAsAsked(loaded, pipeline: pipeline, settings: settings)
        guard settings.mode == .compress else { return output }
        return keepOriginalIfSmaller(output, loaded: loaded, settings: settings)
    }

    /// Comprimir never hands back a bigger file than the one it was given. The original bytes win instead,
    /// except when metadata must go: then a JPEG is rewritten losslessly without it, and other formats keep
    /// the (larger) clean output, since handing back the original would leak the location it was asked to remove.
    static func keepOriginalIfSmaller(_ output: EncodedOutput, loaded: LoadedImage, settings: ConvertSettings) -> EncodedOutput {
        let format = settings.outputFormat(for: loaded.url)
        guard OutputFormat.matching(loaded.url) == format, loaded.fileSize > 0, Int64(output.data.count) >= loaded.fileSize else {
            return output
        }
        if settings.stripMetadata {
            var lossless = settings
            lossless.compressQuality = CompressionLevel.lossless.quality
            if format == .jpeg, let clean = losslessJPEG(loaded, settings: lossless), clean.data.count < output.data.count {
                return clean
            }
            return output
        }
        guard let original = try? Data(contentsOf: loaded.url, options: .mappedIfSafe) else { return output }
        return EncodedOutput(data: original, pixelSize: loaded.image.pixelSize, image: nil)
    }

    /// "Sem perdas" for JPEG: rewrite the DCT data with optimised Huffman tables, without decoding the pixels.
    /// Markers are dropped only when the image is upright, since the orientation lives in EXIF.
    static func losslessJPEG(_ loaded: LoadedImage, settings: ConvertSettings) -> EncodedOutput? {
        guard settings.mode == .compress, settings.compressQuality >= CompressionLevel.lossless.quality,
              loaded.sourceType == "public.jpeg",
              let data = try? Data(contentsOf: loaded.url, options: .mappedIfSafe) else { return nil }
        let upright = (loaded.properties.raw[kCGImagePropertyOrientation] as? Int ?? 1) == 1
        let size = loaded.image.pixelSize
        let rect = PixelRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let out = try? LibJPEG.losslessCrop(data, rect: rect, keepMarkers: !(settings.stripMetadata && upright),
                                                  progressive: false, dpiX: 0, dpiY: 0) else { return nil }
        return EncodedOutput(data: out, pixelSize: size, image: nil)
    }

    private static func encodeAsAsked(_ loaded: LoadedImage, pipeline: ImagePipeline, settings: ConvertSettings) throws -> EncodedOutput {
        let format = settings.outputFormat(for: loaded.url)
        if format == .jpeg, let lossless = losslessJPEG(loaded, settings: settings),
           settings.maxFileSizeBytes.map({ lossless.data.count <= $0 }) ?? true {
            return lossless
        }
        let formatSettings = settings.effectiveFormatSettings
        let first = try pipeline.encode(loaded, format: format, settings: formatSettings)
        guard let limit = settings.maxFileSizeBytes, first.data.count > limit,
              let start = formatSettings.quality(for: format), let image = first.image else { return first }
        // Binary-search the highest quality that fits; the processed pixels are reused for every attempt.
        let dpi = pipeline.options.dpi.enabled ? (pipeline.options.dpi.x, pipeline.options.dpi.y)
            : (loaded.metadata.dpiX ?? 72, loaded.metadata.dpiY ?? 72)
        let input = ImageEncoder.Input(image: image, sourceProperties: loaded.properties, sourceJPEGQuality: nil,
                                       dpiX: dpi.0, dpiY: dpi.1)
        func attempt(_ q: Int) throws -> Data {
            try ImageEncoder.encode(input, format: format, settings: formatSettings.with(quality: q, for: format))
        }
        var low = 5, high = min(start, 100) - 1
        var best = try attempt(low)
        guard best.count <= limit else { return EncodedOutput(data: best, pixelSize: first.pixelSize, image: image) }
        while low < high {
            let mid = (low + high + 1) / 2
            let data = try attempt(mid)
            if data.count <= limit { best = data; low = mid } else { high = mid - 1 }
        }
        return EncodedOutput(data: best, pixelSize: first.pixelSize, image: image)
    }
}
