import Foundation
import ImageIO

/// ImageIO properties dictionary carried between threads untouched.
public struct ImageProperties: @unchecked Sendable {
    public let raw: [CFString: Any]
    public static let empty = ImageProperties(raw: [:])
}

/// A decoded, upright (EXIF orientation applied) source image.
public struct LoadedImage: @unchecked Sendable {
    public let url: URL
    public let image: CGImage
    public let properties: ImageProperties
    public let metadata: ImageMetadata
    public let sourceType: String?
    public let fileSize: Int64
    public let modificationDate: Date
    public let creationDate: Date?

    public init(url: URL, image: CGImage, properties: ImageProperties, metadata: ImageMetadata, sourceType: String?,
                fileSize: Int64, modificationDate: Date, creationDate: Date?) {
        self.url = url
        self.image = image
        self.properties = properties
        self.metadata = metadata
        self.sourceType = sourceType
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.creationDate = creationDate
    }

    /// Horizontal DPI declared by the file, or 72.
    public var dpi: Double { metadata.dpiX ?? 72 }
}

public enum ImageLoader {
    public static func load(_ url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw ImagingError.unreadable(url.lastPathComponent)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard let image = uprightImage(source, properties: properties) else {
            throw ImagingError.unreadable(url.lastPathComponent)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        var metadata = ImageMetadata(properties: properties)
        if CGImageSourceGetType(source) as String? == "public.jpeg" {
            metadata.jpegQuality = JPEGQualityEstimator.estimate(url: url)
        }
        return LoadedImage(
            url: url, image: image, properties: ImageProperties(raw: properties), metadata: metadata,
            sourceType: CGImageSourceGetType(source) as String?,
            fileSize: Int64(values?.fileSize ?? 0),
            modificationDate: values?.contentModificationDate ?? Date(),
            creationDate: values?.creationDate)
    }

    /// Small, oriented preview for lists; never decodes the full image.
    public static func thumbnail(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Pixel size after orientation, read from the header only.
    public static func pixelSize(_ url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = p[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? PixelSize(width: h, height: w) : PixelSize(width: w, height: h)
    }

    private static func uprightImage(_ source: CGImageSource, properties: [CFString: Any]) -> CGImage? {
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1 { return CGImageSourceCreateImageAtIndex(source, 0, nil) }
        let w = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        // Without a known size, omit the cap so ImageIO decodes at full resolution instead of 0 px.
        if max(w, h) > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = max(w, h) }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
