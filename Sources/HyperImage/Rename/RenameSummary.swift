import HyperImageCore
import SwiftUI

/// Pinned card: count, example of the new name, the Renomear button and undo.
struct RenameSummary: View {
    @Environment(AppModel.self) private var app
    let start: () -> Void
    @State private var example: String?

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Renomear").font(.callout.weight(.semibold))
                    Spacer()
                    Text(app.inputs.count == 1 ? String(localized: "1 arquivo") : String(localized: "\(app.inputs.count) arquivos"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let example {
                    Text("Exemplo: \(example)").font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                Text("Os arquivos originais serão renomeados.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)) }

            Button(action: start) {
                Label("Renomear arquivos", systemImage: "character.cursor.ibeam")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(app.inputs.isEmpty)
            .help("⌘↩ · mostra a pré-visualização antes de renomear")

            if !app.lastRename.isEmpty {
                VStack(spacing: 2) {
                    Button("Desfazer renomeação", systemImage: "arrow.uturn.backward") { app.undoLastRename() }
                        .buttonStyle(.borderless)
                    Text("\(app.lastRename.count) arquivo(s) renomeado(s)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: ExampleKey(settings: app.state.rename, revision: app.inputsRevision)) {
            guard let first = app.inputs.first?.url else { example = nil; return }
            let settings = app.state.rename
            let work = Task.detached(priority: .utility) {
                BatchRename.plan([first], settings: settings, dates: BatchConverter.fileDate).first?.destination.lastPathComponent
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            example = result
        }
    }
}

private struct ExampleKey: Equatable {
    let settings: BatchRenameSettings
    let revision: Int
}
