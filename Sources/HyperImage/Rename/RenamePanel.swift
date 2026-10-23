import HyperImageCore
import SwiftUI

/// Cards for the Renomear tab: method, template or search/replace, extension case.
struct RenamePanel: View {
    @Binding var settings: BatchRenameSettings

    var body: some View {
        Group {
            PanelSection(title: "Método") {
                Picker("Método", selection: $settings.method) {
                    Text("Modelo").tag(RenameMethod.template)
                    Text("Substituir").tag(RenameMethod.searchReplace)
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            if settings.method == .template {
                PanelSection(title: "Modelo") {
                    TemplateField(template: $settings.template)
                    if RenameTemplate.usesSequence(settings.template) {
                        Stepper("Começar em \(settings.startNumber)", value: $settings.startNumber, in: 0...9_999_999)
                    }
                    Text("# número · * nome original · $P pasta · $Y $M $D data · $H $N $S hora")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                PanelSection(title: "Buscar e substituir") {
                    PairRow(label: "Texto 1", pair: $settings.searchReplace.pairs[0])
                    PairRow(label: "Texto 2", pair: $settings.searchReplace.pairs[1])
                    PairRow(label: "Texto 3", pair: $settings.searchReplace.pairs[2])
                    PairRow(label: "Extensão", pair: $settings.searchReplace.extensionPair)
                    ToggleRow(title: "Diferenciar maiúsculas", isOn: $settings.searchReplace.caseSensitive)
                }
            }
            PanelSection(title: "Extensão") {
                Picker("Extensão", selection: $settings.extensionCase) {
                    Text("Sem mudança").tag(ExtensionCase.noChange)
                    Text("minúsculas").tag(ExtensionCase.lower)
                    Text("MAIÚSCULAS").tag(ExtensionCase.upper)
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }
            PanelSection(title: "Ordem") {
                Text("A ordem da lista define a numeração. Use o menu de ordenação acima da lista.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PairRow: View {
    let label: LocalizedStringKey
    @Binding var pair: SearchReplaceRule.Pair

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Buscar", text: $pair.search)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                TextField("Substituir por", text: $pair.replace)
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}
