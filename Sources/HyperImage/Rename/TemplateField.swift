import HyperImageCore
import SwiftUI

/// Template text field with the saved template list and a token cheat sheet.
struct TemplateField: View {
    @Environment(AppModel.self) private var app
    @Binding var template: String
    @State private var editing = false
    @State private var showHelp = false

    var body: some View {
        @Bindable var app = app
        LabeledContent("Modelo") {
            HStack(spacing: 4) {
                TextField("Modelo", text: $template)
                    .font(.body.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Menu {
                    ForEach(app.state.renameTemplates, id: \.self) { t in Button(t) { template = t } }
                    Divider()
                    Button("Editar Lista de Modelos…") { editing = true }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .menuStyle(.button).buttonStyle(.borderless).fixedSize()
                Button("Ajuda", systemImage: "questionmark.circle") { showHelp.toggle() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .popover(isPresented: $showHelp) { TemplateHelp().padding() }
            }
        }
        .sheet(isPresented: $editing) {
            ListEditorSheet(title: "Modelos de nome", items: $app.state.renameTemplates, defaults: StandardSizes.renameTemplates, newItem: "Nome_###") { $value in
                TextField("Modelo", text: $value).font(.body.monospaced())
            }
        }
    }
}

struct TemplateHelp: View {
    private let rows: [(String, String)] = [
        ("#", String(localized: "um dígito do número sequencial (zeros à esquerda)")),
        ("*", String(localized: "nome original do arquivo")),
        ("$P", String(localized: "nome da pasta")),
        ("$Y $M $D", String(localized: "ano, mês, dia")),
        ("$H $N $S", String(localized: "hora, minuto, segundo")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Símbolos do modelo").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).font(.body.monospaced().weight(.semibold))
                        Text(row.1).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text("Exemplos").font(.subheadline.weight(.semibold))
            Text("Image##### → Image00032.jpg\n$P_##### → Ferias_00032.jpg\n$Y-$M-$D_##### → 2026-10-18_00032.jpg\n*_tn → Praia_tn.jpg")
                .font(.callout.monospaced())
            Text("A data usada é a da foto (EXIF) ou, sem EXIF, a de modificação.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 360)
    }
}
