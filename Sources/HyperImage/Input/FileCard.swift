import HyperImageCore
import SwiftUI

/// One queued file as a card: thumbnail, name, details, result and the actions that appear on hover.
struct FileCard: View {
    let item: InputItem
    let record: ConversionRecord?
    let isRunning: Bool
    let isSelected: Bool
    var showsRatio = true
    var canPreview = true
    /// 0…1 while this file is being upscaled.
    var working: Double?
    let preview: () -> Void
    let remove: () -> Void
    @State private var dimensions = ""
    @State private var fileSize: Int64 = 0
    @State private var hovering = false
    @State private var removeHover = false

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
                            .help("Será salvo na subpasta \"\(folder)\" da saída")
                    }
                }
                Text(details).font(.caption).foregroundStyle(detailsColor).lineLimit(1).truncationMode(.tail).monospacedDigit()
            }
            Spacer(minLength: 8)
            result
            if canPreview, hovering, !isRunning {
                Button(action: preview) {
                    Image(systemName: "eye").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Pré-visualizar (barra de espaço)")
                .accessibilityLabel("Pré-visualizar \(item.url.lastPathComponent)")
                .transition(.opacity)
            }
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(removeHover ? Color.red.opacity(0.18) : .clear, in: .rect(cornerRadius: 7))
                    .foregroundStyle(removeHover ? .red : .secondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { removeHover = $0 }
            .help("Remover da lista")
            .accessibilityLabel("Remover \(item.url.lastPathComponent)")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.background.secondary),
                    in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08))
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        // One VoiceOver element per file instead of five loose labels.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(item.url.lastPathComponent), \(details)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("Pré-visualizar")) { if canPreview { preview() } }
        .accessibilityAction(named: Text("Remover")) { remove() }
        .task(id: item.url) {
            let url = item.url
            let (size, bytes) = await Task.detached(priority: .utility) { (ImageLoader.pixelSize(url), BatchConverter.fileSize(url)) }.value
            dimensions = size.map { "\($0.width) × \($0.height)" } ?? ""
            fileSize = bytes
        }
    }

    private var details: String {
        var parts = [fileSize > 0 ? formatBytes(fileSize) : nil, dimensions.isEmpty ? nil : dimensions]
        switch record?.status {
        case .done?: parts.append(String(localized: "Concluído"))
        case .skipped?: parts.append(String(localized: "Pulado: já existia"))
        case let .failed(message)?: parts.append(String(localized: "Erro: \(message)"))
        case .working?: parts.append(String(localized: "Processando…"))
        case .pending?, nil:
            if let working { parts.append(String(localized: "Processando… \(Int(working * 100)) %")) }
            else { parts.append(isRunning ? String(localized: "Na fila") : String(localized: "Pronto")) }
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var detailsColor: Color {
        switch record?.status {
        case .failed?: .red
        case .skipped?: .orange
        default: .secondary
        }
    }

    @ViewBuilder
    private var result: some View {
        switch record?.status {
        case .done?:
            if let record {
                VStack(alignment: .trailing, spacing: 2) {
                    // Upscale grows the file on purpose, so the result is the new pixel size, not a percentage.
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
        case .failed?:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).accessibilityLabel("Erro")
        case .skipped?:
            Image(systemName: "forward.fill").foregroundStyle(.orange).accessibilityLabel("Pulado")
        case .pending?, .working?, nil:
            if isRunning { ProgressView().controlSize(.small) }
        }
    }
}
