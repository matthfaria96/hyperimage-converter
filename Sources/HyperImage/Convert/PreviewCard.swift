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
struct PreviewSection: View {
    @Environment(AppModel.self) private var app
    let item: InputItem
    @State private var info: PreviewInfo?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                ThumbnailView(url: item.url, maxPixels: 512)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(.rect(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .id(item.url)
                    .transition(.blurReplace)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) {
                        if let info {
                            Text(info.size.map { "\(String($0.width)) × \(String($0.height))" } ?? "—")
                            Text("·")
                            Text(formatBytes(info.bytes))
                            Text("·")
                            Text(info.date.formatted(date: .abbreviated, time: .shortened))
                        } else {
                            Text("Lendo…")
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.opacity)
                }
            }
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text("Pré-visualização")
                Spacer()
                Button("Ocultar", systemImage: "eye.slash") { app.state.showPreview = false }
                    .buttonStyle(.borderless).labelStyle(.iconOnly)
                    .help("Ocultar a pré-visualização (volte a mostrar no menu … da barra)")
            }
        }
        .task(id: item.url) {
            info = nil
            let url = item.url
            let loaded = await Task.detached(priority: .utility) { PreviewInfo.load(url) }.value
            // A slower read of the previous selection must not overwrite the new file's details.
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { info = loaded }
        }
    }
}
