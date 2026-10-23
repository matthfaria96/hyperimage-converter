import AppKit
import HyperImageCore
import SwiftUI

/// Past batches with their files: open, show in Finder, or drag the result out again.
struct HistorySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClear = false

    var body: some View {
        let history = app.history
        VStack(spacing: 0) {
            HStack {
                Text("Histórico").font(.headline)
                Spacer()
                Button("Limpar histórico", systemImage: "trash") { confirmingClear = true }
                    .disabled(history.entries.isEmpty)
                    .confirmationDialog("Limpar o histórico?", isPresented: $confirmingClear) {
                        Button("Limpar histórico", role: .destructive) { withAnimation(.snappy) { history.clear() } }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("Os arquivos convertidos não são apagados, só a lista.")
                    }
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 16).padding(.vertical, 12)
            if history.entries.isEmpty {
                ContentUnavailableView("Nada por aqui ainda", systemImage: "clock.arrow.circlepath",
                                       description: Text("As imagens convertidas, comprimidas e ampliadas aparecem aqui."))
                    .frame(maxHeight: .infinity)
                    .transition(.blurReplace)
            } else {
                List {
                    ForEach(history.batches, id: \.first?.batch) { batch in
                        Section {
                            ForEach(batch) { entry in
                                HistoryRow(entry: entry, isNew: entry.batch == history.latestBatch)
                            }
                        } header: {
                            BatchHeader(batch: batch)
                        }
                    }
                }
                .listStyle(.inset)
                .animation(.snappy, value: history.entries.map(\.id))
            }
            Divider()
            HStack {
                Text(summary).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .padding(14)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private var summary: String {
        let done = app.history.entries.filter { $0.error == nil }
        let saved = done.reduce(Int64(0)) { $0 + max(0, $1.oldSize - $1.newSize) }
        let files = done.count == 1 ? String(localized: "1 arquivo") : String(localized: "\(done.count) arquivos")
        return saved > 0 ? String(localized: "\(files) · \(formatBytes(saved)) economizados") : files
    }
}

private struct BatchHeader: View {
    let batch: [HistoryEntry]

    var body: some View {
        let first = batch[0]
        let saved = batch.filter { $0.error == nil }.reduce(Int64(0)) { $0 + max(0, $1.oldSize - $1.newSize) }
        HStack(spacing: 6) {
            Label(first.mode.historyTitle, systemImage: first.mode.symbol)
            Text("·")
            Text(first.date.formatted(date: .abbreviated, time: .shortened))
            Spacer()
            if saved > 0 && first.mode != .upscale { Text("−\(formatBytes(saved))").foregroundStyle(.green) }
        }
        .monospacedDigit()
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var app
    let entry: HistoryEntry
    let isNew: Bool
    @State private var exists = true

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: exists && entry.error == nil ? entry.output : entry.source, maxPixels: 120)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: .rect(cornerRadius: 6))
                .clipShape(.rect(cornerRadius: 6))
                .saturation(entry.error == nil && exists ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.output.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if isNew {
                        Text("Novo").font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor, in: .capsule)
                    }
                }
                Text(detail).font(.callout).foregroundStyle(entry.error == nil ? Color.secondary : .red).lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if entry.error == nil && exists {
                Button("Abrir", systemImage: "eye") { NSWorkspace.shared.open(entry.output) }
                    .labelStyle(.iconOnly).help("Abrir no Pré-Visualização")
                Button("Mostrar no Finder", systemImage: "folder") { FilePanels.reveal([entry.output]) }
                    .labelStyle(.iconOnly).help("Mostrar no Finder")
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
        .contextMenu {
            if entry.error == nil && exists {
                Button("Abrir") { NSWorkspace.shared.open(entry.output) }
                Button("Mostrar no Finder") { FilePanels.reveal([entry.output]) }
            }
            Button("Mostrar original no Finder") { FilePanels.reveal([entry.source]) }
            Divider()
            Button("Remover do histórico", role: .destructive) { withAnimation(.snappy) { app.history.remove([entry.id]) } }
        }
        .modifier(HistoryDrag(url: entry.error == nil && exists ? entry.output : nil))
        .task(id: entry.output) {
            let url = entry.output
            exists = await Task.detached(priority: .utility) { FileManager.default.fileExists(atPath: url.path) }.value
        }
    }

    private var detail: String {
        if let error = entry.error { return error }
        if !exists { return String(localized: "Arquivo movido ou apagado") }
        guard entry.oldSize > 0, entry.newSize > 0 else { return formatBytes(entry.newSize) }
        let change = Int((Double(entry.newSize - entry.oldSize) / Double(entry.oldSize) * 100).rounded())
        let sign = change > 0 ? "+" : ""
        return "\(formatBytes(entry.oldSize)) → \(formatBytes(entry.newSize)) (\(sign)\(change) %)"
    }
}

private struct HistoryDrag: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url { content.draggable(url) } else { content }
    }
}

extension ConvertMode {
    var historyTitle: LocalizedStringKey {
        switch self {
        case .convert: "Conversão"
        case .compress: "Compressão"
        case .upscale: "AI Upscale"
        }
    }
}
