import Foundation
import ImageIO

/// Adds EXIF/IPTC/GPS/TIFF metadata to an already-compressed JPEG without touching its scan data.
enum JPEGMetadataWriter {
    /// The JPEG with the metadata merged in, or nil when ImageIO could not rewrite it.
    static func attach(_ properties: [CFString: Any], to jpeg: Data) -> Data? {
        guard !properties.isEmpty,
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let metadata = CGImageMetadataCreateMutable()
        for (dictionaryName, value) in properties {
            guard let dictionary = value as? [CFString: Any] else { continue }
            for (key, item) in dictionary {
                _ = CGImageMetadataSetValueMatchingImageProperty(metadata, dictionaryName, key, item as CFTypeRef)
            }
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else { return nil }
        return output as Data
    }
}
