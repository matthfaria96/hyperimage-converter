import HyperImageCore
import SwiftUI

struct ConvertInspector: View {
    @Environment(AppModel.self) private var app
    let open: (SheetRoute) -> Void

    var body: some View {
        @Bindable var app = app
        let settings = $app.state.convert
        Form {
            Section("Saída") {
                Picker("Formato", selection: settings.format) {
                    ForEach(OutputFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Button("Ajustes de \(app.state.convert.format.displayName)…") { open(.formatSettings) }
                Toggle("Salvar em outra pasta", isOn: settings.useOutputFolder)
                if app.state.convert.useOutputFolder {
                    OutputFolderRow(path: settings.outputFolder)
                    if app.hasFolderItems {
                        Toggle("Manter estrutura de pastas", isOn: settings.keepFolderStructure)
                    }
                } else {
                    Text("Os arquivos convertidos ficam ao lado dos originais.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Processamento") {
                Toggle("Usar opções avançadas", isOn: settings.useAdvancedOptions)
                Button("Configurar Opções Avançadas…") { open(.advanced) }
                if app.state.convert.useAdvancedOptions {
                    ActiveStepsSummary(options: app.state.convert.advanced)
                }
            }

            Section("Renomear") {
                Toggle("Renomear arquivos de saída", isOn: settings.rename)
                if app.state.convert.rename {
                    TemplateField(template: settings.renameTemplate)
                    if RenameTemplate.usesSequence(app.state.convert.renameTemplate) {
                        Stepper("Começar em \(app.state.convert.renameStartNumber)", value: settings.renameStartNumber, in: 0...9_999_999)
                    }
                }
            }

            Section("Opções") {
                Toggle("Extensão em MAIÚSCULAS", isOn: settings.uppercaseExtension)
                Toggle("Manter data e hora originais", isOn: settings.keepDates)
                Toggle("Perguntar antes de sobrescrever", isOn: settings.askBeforeOverwrite)
                Toggle("Mostrar mensagens de erro", isOn: settings.showErrors)
                Toggle("Processar várias imagens ao mesmo tempo (mais rápido)", isOn: settings.parallel)
            }

            PreviewSection()
        }
        .formStyle(.grouped)
    }
}

struct PreviewSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Toggle("Mostrar pré-visualização", isOn: $app.state.showPreview)
            if app.state.showPreview, let item = app.selectedItem {
                SelectedPreview(url: item.url)
            }
        }
    }
}

private struct OutputFolderRow: View {
    @Binding var path: String

    var body: some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text(path.isEmpty ? String(localized: "Nenhuma pasta escolhida") : (path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1).truncationMode(path.isEmpty ? .tail : .head)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
                .help(path)
            Spacer()
            Button("Escolher…") {
                if let url = FilePanels.chooseFolder(startingAt: path) { path = url.path }
            }
            Button("Mostrar", systemImage: "arrow.right.circle") {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
            .labelStyle(.iconOnly)
            .disabled(path.isEmpty)
        }
    }
}

/// Small capsules naming the enabled Advanced Options steps.
struct ActiveStepsSummary: View {
    let options: AdvancedOptions

    var body: some View {
        let steps = AdvancedStep.allCases.filter { $0.isEnabled(in: options) }
        if steps.isEmpty {
            Text("Nenhuma etapa ativada").font(.caption).foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(steps) { step in
                    Label(step.title, systemImage: step.symbol)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: .capsule)
                }
            }
        }
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
