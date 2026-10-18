import HyperImageCore
import SwiftUI

/// Old → new names; conflicting rows are flagged and skipped.
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
            HStack {
                let conflicts = entries.filter(\.conflict).count
                let changes = entries.filter { !$0.unchanged && !$0.conflict }.count
                (conflicts > 0 ? Text("\(changes) a renomear · \(conflicts) em conflito") : Text("\(changes) a renomear")).foregroundStyle(.secondary)
                Spacer()
                Button("Fechar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Renomear") { rename() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(changes == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 480)
        .task {
            let files = app.inputs.map(\.url), settings = app.state.rename
            entries = await Task.detached {
                BatchRename.plan(files, settings: settings, dates: BatchConverter.fileDate)
            }.value
        }
    }

    private func rename() {
        let outcome = BatchRename.execute(entries)
        let failed = Set(outcome.failures.map(\.0))
        let moved = entries.filter { !$0.unchanged && !$0.conflict && !failed.contains($0.source) }
        app.replace(Dictionary(uniqueKeysWithValues: moved.map { ($0.source, $0.destination) }))
        if !outcome.failures.isEmpty {
            app.alert = AppAlert(title: String(localized: "\(outcome.failures.count) arquivo(s) não renomeado(s)"),
                                 message: outcome.failures.prefix(8).map { "\($0.0.lastPathComponent): \($0.1)" }.joined(separator: "\n"))
        }
        dismiss()
    }
}
