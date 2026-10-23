import HyperImageCore
import SwiftUI

/// Old to new names; conflicting rows are flagged and skipped. The only path to `applyRename`.
struct RenamePreviewSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [RenameEntry] = []

    var body: some View {
        let (changes, conflicts) = BatchRename.counts(entries)
        VStack(spacing: 0) {
            Text("Pré-visualização da renomeação").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Table(entries) {
                TableColumn("Nº") { e in Text("\(e.number)").monospacedDigit().foregroundStyle(.secondary) }.width(40)
                TableColumn("Pasta") { e in Text(e.source.deletingLastPathComponent().lastPathComponent).foregroundStyle(.secondary) }
                TableColumn("Nome atual") { e in Text(e.source.lastPathComponent) }
                TableColumn("Novo nome") { e in
                    HStack {
                        Text(e.destination.lastPathComponent).foregroundStyle(e.conflict ? .red : (e.unchanged ? .secondary : .primary))
                        if e.conflict { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help("Nome em conflito — será ignorado") }
                    }
                }
            }
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if entries.isEmpty && !app.inputs.isEmpty { ProgressView() }
            }
            Divider()
            HStack {
                Label {
                    conflicts > 0 ? Text("\(changes) a renomear · \(conflicts) em conflito") : Text("\(changes) a renomear")
                } icon: {
                    Image(systemName: conflicts > 0 ? "exclamationmark.triangle.fill" : "character.cursor.ibeam")
                        .foregroundStyle(conflicts > 0 ? .orange : .secondary)
                }
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Renomear") {
                    app.applyRename(entries)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(changes == 0)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(14)
            .background(.bar)
        }
        .frame(minWidth: 760, minHeight: 420)
        .animation(.snappy, value: entries.count)
        .task {
            let files = app.inputs.map(\.url), settings = app.state.rename
            let work = Task.detached(priority: .userInitiated) {
                BatchRename.plan(files, settings: settings, dates: BatchConverter.fileDate)
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            entries = result
        }
    }
}
