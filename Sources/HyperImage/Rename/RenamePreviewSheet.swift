import HyperImageCore
import SwiftUI

/// Old to new names; conflicting rows are flagged and skipped. The only path to `applyRename`.
struct RenamePreviewSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [RenameEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pré-visualização da renomeação").font(.title3.weight(.semibold))
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
            .overlay { if entries.isEmpty && !app.inputs.isEmpty { ProgressView() } }
            HStack {
                let (changes, conflicts) = BatchRename.counts(entries)
                (conflicts > 0 ? Text("\(changes) a renomear · \(conflicts) em conflito") : Text("\(changes) a renomear")).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Renomear") {
                    app.applyRename(entries)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(changes == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 480)
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
