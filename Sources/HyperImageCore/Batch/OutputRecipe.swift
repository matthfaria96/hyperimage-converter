import Foundation

public enum ConvertMode: String, Codable, CaseIterable, Sendable {
    case convert, compress, upscale, rename
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
        case .rename: format
        }
    }

    public var nameSuffix: String {
        // Upscaled files always get a suffix: same-format outputs next to the originals would collide otherwise.
        if mode == .upscale { return "-upscale-\(upscale.scale)x" }
        guard addSuffix else { return "" }
        return mode == .compress ? String(localized: "-comprimido") : String(localized: "-convertido")
    }

    /// Advanced Options when enabled, plus the quick "limit dimensions" resize when it does not clash with them.
    public var effectiveAdvancedOptions: AdvancedOptions {
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

    public var effectiveFormatSettings: FormatSettings {
        var settings = formatSettings
        settings.flattenTransparency = !preserveTransparency
        if !preserveTransparency { settings.gif.transparent = false }
        return settings
    }

    public var maxFileSizeBytes: Int? { limitFileSize && maxFileSizeKB > 0 ? maxFileSizeKB * 1024 : nil }
}

/// Encodes one loaded file with everything the settings ask for, including the file-size target.
public enum OutputEncoder {
    public static func encode(_ loaded: LoadedImage, pipeline: ImagePipeline, settings: ConvertSettings) throws -> EncodedOutput {
        let format = settings.outputFormat(for: loaded.url)
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
