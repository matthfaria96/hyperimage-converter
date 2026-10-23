import HyperImageCore
import SwiftUI

/// Metadata of the selected file, read off the main thread.
struct PreviewInfo: Equatable, Sendable {
    let size: PixelSize?
    let bytes: Int64
    let date: Date

    nonisolated static func load(_ url: URL) -> PreviewInfo {
        PreviewInfo(size: ImageLoader.pixelSize(url), bytes: BatchConverter.fileSize(url), date: BatchConverter.fileDate(url))
    }
}

/// Thumbnail, dimensions, size and date of the single selected file (FastStone style).
struct PreviewCard: View {
    @Environment(AppModel.self) private var app
    let item: InputItem
    @State private var info: PreviewInfo?

    var body: some View {
        PanelSection(title: "Pré-visualização") {
            ThumbnailView(url: item.url, maxPixels: 512)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(.rect(cornerRadius: 6))
            Text(item.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            if let info {
                let dims = info.size.map { "\(String($0.width)) × \(String($0.height))" } ?? "—"
                VStack(alignment: .leading, spacing: 2) {
                    Text(dims)
                    Text("\(formatBytes(info.bytes)) · \(info.date.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Spacer()
                Button("Ocultar", systemImage: "eye.slash") { app.state.showPreview = false }
                    .buttonStyle(.borderless).font(.caption)
                    .help("Ocultar a pré-visualização (volte a mostrar no menu … da lista)")
            }
        }
        .task(id: item.url) {
            info = nil
            let url = item.url
            let loaded = await Task.detached(priority: .utility) { PreviewInfo.load(url) }.value
            // A slower read of the previous selection must not overwrite the new file's details.
            guard !Task.isCancelled else { return }
            info = loaded
        }
    }
}
