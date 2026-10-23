import HyperImageCore
import SwiftUI

/// One queued file as a list row: thumbnail, name, details, result and the actions that appear on hover.
struct FileRow: View {
    let item: InputItem
    let record: ConversionRecord?
    let isRunning: Bool
    var showsRatio = true
    var canPreview = true
    /// 0…1 while this file is being upscaled.
    var working: Double?
    let preview: () -> Void
    let remove: () -> Void
    @State private var dimensions = ""
    @State private var fileSize: Int64 = 0
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: item.url, maxPixels: 120)
                .frame(width: 44, height: 44)
                .background(.quaternary, in: .rect(cornerRadius: 6))
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent).font(.body).lineLimit(1).truncationMode(.middle)
                    if let folder = item.virtualFolder {
                        Label(folder, systemImage: "folder.badge.plus")
                            .font(.caption).foregroundStyle(.tint).lineLimit(1)
                            .help("Será salvo na subpasta \"\(folder)\" da saída")
                    }
                }
                Text(details).font(.callout).foregroundStyle(detailsColor).lineLimit(1).truncationMode(.tail).monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            result
            if canPreview, hovering, !isRunning {
                Button(action: preview) {
                    Image(systemName: "eye").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Pré-visualizar (barra de espaço)")
                .accessibilityLabel("Pré-visualizar \(item.url.lastPathComponent)")
                .transition(.opacity)
            }
            if hovering, !isRunning {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remover da lista")
                .accessibilityLabel("Remover \(item.url.lastPathComponent)")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.snappy, value: record?.status)
        // One VoiceOver element per file instead of five loose labels.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(item.url.lastPathComponent), \(details)"))
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
            else if isRunning { parts.append(String(localized: "Na fila")) }
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
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        // Upscale grows the file on purpose, so the result is the new pixel size, not a percentage.
                        Text(formatBytes(record.newSize)).font(.body.weight(.medium)).monospacedDigit()
                        if showsRatio, let ratio = record.ratio {
                            let change = Int(((ratio - 1) * 100).rounded())
                            Text(change <= 0 ? "\(change) %" : "+\(change) %")
                                .font(.caption.weight(.medium)).monospacedDigit()
                                .foregroundStyle(change <= 0 ? .green : .orange)
                        }
                    }
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .symbolEffect(.bounce, value: record.status == .done)
                        .accessibilityHidden(true)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        case .failed?:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).accessibilityLabel("Erro")
                .transition(.scale.combined(with: .opacity))
        case .skipped?:
            Image(systemName: "forward.fill").foregroundStyle(.orange).accessibilityLabel("Pulado")
                .transition(.scale.combined(with: .opacity))
        case .working?:
            ProgressView().controlSize(.small).transition(.opacity)
        case .pending?, nil:
            if let working {
                ProgressView(value: working).progressViewStyle(.circular).controlSize(.small).transition(.opacity)
            } else if isRunning {
                Image(systemName: "clock").foregroundStyle(.tertiary).transition(.opacity)
            }
        }
    }
}
