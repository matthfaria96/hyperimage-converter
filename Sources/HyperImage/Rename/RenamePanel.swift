import HyperImageCore
import SwiftUI

/// Form sections for the Renomear tab: method, template or search/replace, extension case.
struct RenamePanel: View {
    @Binding var settings: BatchRenameSettings

    var body: some View {
        Section {
            Picker("Método", selection: $settings.method.animation(.snappy)) {
                Text("Modelo").tag(RenameMethod.template)
                Text("Buscar e substituir").tag(RenameMethod.searchReplace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        } header: {
            Text("Método")
        }
        if settings.method == .template {
            Section {
                TemplateField(template: $settings.template)
                if RenameTemplate.usesSequence(settings.template) {
                    Stepper("Começar em \(settings.startNumber)", value: $settings.startNumber, in: 0...9_999_999)
                        .transition(.blurReplace)
                }
            } header: {
                Text("Novo nome")
            } footer: {
                Text("# número · * nome original · $P pasta · $Y $M $D data · $H $N $S hora")
            }
            .transition(.blurReplace)
        } else {
            Section {
                PairRow(label: "Texto 1", pair: $settings.searchReplace.pairs[0])
                PairRow(label: "Texto 2", pair: $settings.searchReplace.pairs[1])
                PairRow(label: "Texto 3", pair: $settings.searchReplace.pairs[2])
                PairRow(label: "Extensão", pair: $settings.searchReplace.extensionPair)
                Toggle("Diferenciar maiúsculas", isOn: $settings.searchReplace.caseSensitive)
            } header: {
                Text("Buscar e substituir")
            }
            .transition(.blurReplace)
        }
        Section {
            Picker("Extensão", selection: $settings.extensionCase) {
                Text("Sem mudança").tag(ExtensionCase.noChange)
                Text("minúsculas").tag(ExtensionCase.lower)
                Text("MAIÚSCULAS").tag(ExtensionCase.upper)
            }
        } footer: {
            Text("A ordem da lista define a numeração. Use o menu Ordenar da barra de ferramentas.")
        }
    }
}

private struct PairRow: View {
    let label: LocalizedStringKey
    @Binding var pair: SearchReplaceRule.Pair

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("Buscar", text: $pair.search)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                TextField("Substituir por", text: $pair.replace)
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}
