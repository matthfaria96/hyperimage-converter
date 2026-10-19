import HyperImageCore
import SwiftUI

/// One queued file as a card: thumbnail, name, details, result size and a remove button.
struct FileCard: View {
    let item: InputItem
    let record: ConversionRecord?
    let isRunning: Bool
    let isSelected: Bool
    var showsRatio = true
    /// 0…1 while this file is being upscaled.
    var working: Double?
    let remove: () -> Void
    @State private var dimensions = ""
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ThumbnailView(url: item.url, maxPixels: 120)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 7))
                .background(.quaternary, in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    if let folder = item.virtualFolder {
                        Label(folder, systemImage: "folder.badge.plus")
                            .font(.caption2).foregroundStyle(.tint).lineLimit(1)
                            .help("Será salvo na subpasta \"\(folder)\" da pasta de saída")
                    }
                }
                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
            }
            Spacer(minLength: 8)
            result
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(hovering ? Color.red.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                    .foregroundStyle(hovering ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Remover da lista")
            .accessibilityLabel("Remover \(item.url.lastPathComponent)")
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.background.secondary),
                    in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08))
        }
        .contentShape(.rect)
        .task(id: item.url) {
            let size = await Task.detached(priority: .utility) { ImageLoader.pixelSize(item.url) }.value
            dimensions = size.map { "\($0.width) × \($0.height)" } ?? ""
        }
    }

    private var details: String {
        let bytes = formatBytes(BatchConverter.fileSize(item.url))
        let status: String = switch record?.status {
        case .done?: String(localized: "Concluído")
        case .skipped?: String(localized: "Pulado")
        case .failed?: String(localized: "Erro")
        case .working?: String(localized: "Processando…")
        case .pending?, nil:
            if let working { String(localized: "Processando… \(Int(working * 100)) %") }
            else { isRunning ? String(localized: "Na fila") : String(localized: "Pronto") }
        }
        return [bytes, dimensions.isEmpty ? nil : dimensions, status].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var result: some View {
        switch record?.status {
        case .done?:
            if let record {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatBytes(record.newSize)).font(.callout.weight(.semibold)).monospacedDigit()
                    if showsRatio, let ratio = record.ratio {
                        let change = Int(((ratio - 1) * 100).rounded())
                        Text(change <= 0 ? "\(change) %" : "+\(change) %")
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(change <= 0 ? .green : .orange)
                    }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        case let .failed(message)?:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(message)
        case .skipped?:
            Image(systemName: "forward.fill").foregroundStyle(.orange).help("Arquivo já existia")
        case .pending?, .working?, nil:
            if isRunning { ProgressView().controlSize(.small) }
        }
    }
}
