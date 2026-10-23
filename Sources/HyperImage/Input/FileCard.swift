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
    /// Comprimir before running: estimate this file's new size with these settings.
    var estimateSettings: ConvertSettings?
    let preview: () -> Void
    let remove: () -> Void
    @State private var dimensions = ""
    @State private var fileSize: Int64 = 0
    @State private var hovering = false
    @State private var estimated: Int64?

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
        .task(id: RowEstimateKey(url: item.url, settings: estimateSettings)) {
            guard let settings = estimateSettings else { estimated = nil; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let bytes = await RowEstimates.shared.size(of: item.url, settings: settings)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { estimated = bytes }
        }
        .modifier(DragOutResult(url: record?.status == .done ? record?.output : nil))
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
            } else if estimateSettings != nil, let estimated, fileSize > 0 {
                let change = Int((Double(estimated - fileSize) / Double(fileSize) * 100).rounded())
                VStack(alignment: .trailing, spacing: 1) {
                    Text("≈ \(formatBytes(estimated))").font(.body).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(change < 0 ? "\(change) %" : String(localized: "sem ganho"))
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .foregroundStyle(change < 0 ? Color.green.opacity(0.8) : .secondary)
                }
                .help("Tamanho estimado depois de comprimir")
                .transition(.blurReplace)
            }
        }
    }
}

private struct RowEstimateKey: Equatable {
    let url: URL
    let quality: Int?
    let strip: Bool
    let limit: Int?

    init(url: URL, settings: ConvertSettings?) {
        self.url = url
        quality = settings?.compressQuality
        strip = settings?.stripMetadata ?? false
        limit = settings?.maxFileSizeBytes
    }
}

/// Per-file compressed sizes, encoded off the main thread once per file and settings.
actor RowEstimates {
    static let shared = RowEstimates()
    private var cache: [String: Int64] = [:]

    func size(of url: URL, settings: ConvertSettings) async -> Int64? {
        let key = "\(url.path)|\(settings.compressQuality)|\(settings.stripMetadata)|\(settings.maxFileSizeBytes ?? 0)"
        if let hit = cache[key] { return hit }
        let work = Task.detached(priority: .utility) { () -> Int64? in
            guard !Task.isCancelled, let loaded = try? ImageLoader.load(url),
                  let pipeline = try? ImagePipeline(options: settings.effectiveAdvancedOptions),
                  let output = try? OutputEncoder.encode(loaded, pipeline: pipeline, settings: settings) else { return nil }
            return Int64(output.data.count)
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if let result {
            if cache.count > 2000 { cache.removeAll() }
            cache[key] = result
        }
        return result
    }
}

/// A finished row can be dragged straight into Finder, Mail or any app as the converted file.
private struct DragOutResult: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.draggable(url) {
                Label(url.lastPathComponent, systemImage: "photo").padding(6).glassEffect(in: .capsule)
            }
        } else {
            content
        }
    }
}
