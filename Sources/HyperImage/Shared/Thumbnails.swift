import AppKit
import HyperImageCore
import SwiftUI

/// Decodes small previews off the main thread and keeps them in memory.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 600 }

    func image(for url: URL, maxPixels: Int) async -> NSImage? {
        let key = "\(url.path)#\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = ImageLoader.thumbnail(url, maxPixels: maxPixels) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

struct ThumbnailView: View {
    let url: URL
    var maxPixels = 256
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().opacity(0.6)
            }
        }
        .task(id: url) {
            let loaded = await ThumbnailCache.shared.image(for: url, maxPixels: maxPixels)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}
