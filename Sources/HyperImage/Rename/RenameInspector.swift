import HyperImageCore
import SwiftUI

struct RenameInspector: View {
    @Environment(AppModel.self) private var app
    let open: (SheetRoute) -> Void

    var body: some View {
        @Bindable var app = app
        let r = $app.state.rename
        Form {
            Section {
                Text("Renomeia os arquivos originais, no lugar.").font(.callout).foregroundStyle(.secondary)
                Picker("Método", selection: r.method) {
                    Text("Modelo de nome").tag(RenameMethod.template)
                    Text("Buscar e substituir").tag(RenameMethod.searchReplace)
                }
                .pickerStyle(.segmented)
            }
            if app.state.rename.method == .template {
                Section("Modelo") {
                    TemplateField(template: r.template)
                    if RenameTemplate.usesSequence(app.state.rename.template) {
                        Stepper("Começar em \(app.state.rename.startNumber)", value: r.startNumber, in: 0...9_999_999)
                    }
                }
            } else {
                Section("Buscar → Substituir") {
                    ForEach(0..<3, id: \.self) { i in
                        PairRow(title: "Texto \(i + 1)", pair: r.searchReplace.pairs[i])
                    }
                    PairRow(title: "Extensão", pair: r.searchReplace.extensionPair)
                    Toggle("Diferenciar maiúsculas", isOn: r.searchReplace.caseSensitive)
                }
            }
            Section {
                Picker("Extensão", selection: r.extensionCase) {
                    Text("Sem alteração").tag(ExtensionCase.noChange)
                    Text("minúsculas").tag(ExtensionCase.lower)
                    Text("MAIÚSCULAS").tag(ExtensionCase.upper)
                }
                Button("Pré-visualizar e Renomear…") { open(.renamePreview) }
                    .disabled(app.inputs.isEmpty)
            }
            PreviewSection()
        }
        .formStyle(.grouped)
    }
}

private struct PairRow: View {
    let title: String
    @Binding var pair: SearchReplaceRule.Pair

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("Buscar", text: $pair.search)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("Substituir", text: $pair.replace)
            }
        }
    }
}
