import AppKit
import HyperImageCore
import SwiftUI

/// Decodes small previews off the main thread and keeps them in memory.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 600
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL, maxPixels: Int) async -> NSImage? {
        let key = "\(url.path)#\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        // A card scrolled out of view cancels its task; the decode must notice, or fast scrolling queues thousands.
        let work = Task.detached(priority: .utility) { () -> NSImage? in
            guard !Task.isCancelled, let cg = ImageLoader.thumbnail(url, maxPixels: maxPixels) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        let image = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height) * 4)
        }
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
                // A symbol, not NSWorkspace.icon(forFile:), which hits the disk for every card on the main thread.
                Image(systemName: "photo").resizable().scaledToFit().padding(10).foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            let loaded = await ThumbnailCache.shared.image(for: url, maxPixels: maxPixels)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}
