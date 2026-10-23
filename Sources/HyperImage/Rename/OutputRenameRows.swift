import HyperImageCore
import SwiftUI

/// "Renomear a saída" rows for the Save card; the template replaces the suffix when on.
struct OutputRenameRows: View {
    @Binding var settings: ConvertSettings

    var body: some View {
        Toggle("Renomear a saída", isOn: $settings.rename)
            .help("Dá nomes novos aos arquivos gerados; a ordem da lista define a numeração")
        if settings.rename {
            TemplateField(template: $settings.renameTemplate)
            if RenameTemplate.usesSequence(settings.renameTemplate) {
                Stepper("Começar em \(settings.renameStartNumber)", value: $settings.renameStartNumber, in: 0...9_999_999)
            }
        }
    }
}
