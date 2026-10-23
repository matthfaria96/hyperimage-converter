import Foundation

/// A "files of type" filter entry (image types the app reads).
public struct FileTypeFilter: Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let extensions: Set<String>

    public func matches(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
}

public enum ImageFileTypes {
    /// Extensions macOS ImageIO can decode (PCX/WMF/EMF/FAX from the original are not supported by the system).
    public static let readable: Set<String> = [
        "jpg", "jpe", "jpeg", "jfif", "bmp", "gif", "tif", "tiff", "webp", "cur", "ico", "png", "heic", "heif", "hif",
        "avif", "jp2", "j2k", "jpf", "jpx", "tga", "ppm", "pbm", "pgm", "psd", "exr", "dng", "cr2", "cr3", "nef", "arw",
        "raf", "orf", "rw2",
    ]

    public static let filters: [FileTypeFilter] = [
        FileTypeFilter(name: String(localized: "Todos os formatos de imagem"), extensions: readable),
        FileTypeFilter(name: "BMP", extensions: ["bmp"]),
        FileTypeFilter(name: "CUR / ICO", extensions: ["cur", "ico"]),
        FileTypeFilter(name: "GIF", extensions: ["gif"]),
        FileTypeFilter(name: "HEIC / HEIF", extensions: ["heic", "heif", "hif"]),
        FileTypeFilter(name: "AVIF", extensions: ["avif"]),
        FileTypeFilter(name: "JPEG", extensions: ["jpg", "jpeg", "jpe", "jfif"]),
        FileTypeFilter(name: "JPEG 2000", extensions: ["jp2", "j2k", "jpf", "jpx"]),
        FileTypeFilter(name: "PNG", extensions: ["png"]),
        FileTypeFilter(name: "PPM / PBM / PGM", extensions: ["ppm", "pbm", "pgm"]),
        FileTypeFilter(name: "PSD", extensions: ["psd"]),
        FileTypeFilter(name: "RAW", extensions: ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]),
        FileTypeFilter(name: "TGA", extensions: ["tga"]),
        FileTypeFilter(name: "TIFF", extensions: ["tif", "tiff"]),
        FileTypeFilter(name: "WebP", extensions: ["webp"]),
    ]

    public static func isImage(_ url: URL) -> Bool { readable.contains(url.pathExtension.lowercased()) }

    /// Image files inside `folder`, recursively, each with its path relative to `folder` (for "keep folder structure").
    public static func images(in folder: URL) -> [(url: URL, relativeDirectory: String)] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        // Resolve symlinks on both sides: the enumerator may report /private/var/… for a folder given as /var/….
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        var found: [(URL, String)] = []
        for case let url as URL in enumerator where isImage(url) {
            let dir = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            let relative = dir.hasPrefix(root) ? String(dir.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : ""
            let base = folder.lastPathComponent
            found.append((url, relative.isEmpty ? base : "\(base)/\(relative)"))
        }
        return found.sorted { $0.0.path.localizedStandardCompare($1.0.path) == .orderedAscending }
    }
}
