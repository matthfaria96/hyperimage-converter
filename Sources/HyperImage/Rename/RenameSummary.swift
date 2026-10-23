import HyperImageCore
import SwiftUI

/// Floating glass summary for Renomear: count, example of the new name, the button and undo.
struct RenameSummary: View {
    @Environment(AppModel.self) private var app
    let start: () -> Void
    @State private var example: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Exemplo").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(app.inputs.count == 1 ? String(localized: "1 arquivo") : String(localized: "\(app.inputs.count) arquivos"))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Text(example ?? "—").font(.title3.weight(.semibold).monospaced()).lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: example)
                Text("Os arquivos originais serão renomeados.").font(.callout).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Button(action: start) {
                Label("Renomear arquivos", systemImage: "character.cursor.ibeam")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(app.inputs.isEmpty)
            .help("⌘↩ · mostra a pré-visualização antes de renomear")

            if !app.lastRename.isEmpty {
                Button("Desfazer renomeação (\(app.lastRename.count))", systemImage: "arrow.uturn.backward") { app.undoLastRename() }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .transition(.blurReplace)
            }
        }
        .animation(.snappy, value: app.lastRename.isEmpty)
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
