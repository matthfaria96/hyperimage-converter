import HyperImageCore
import SwiftUI

/// The 10 advanced-edit steps, each with its own switch; a step name opens the editor on that step.
struct AdvancedStepsCard: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings

    var body: some View {
        PanelSection(title: "Edição avançada") {
            VStack(spacing: 2) {
                ForEach(AdvancedStep.allCases) { step in
                    row(step)
                }
            }
            if settings.advanced.hasEnabledStep {
                ToggleRow(title: "Aplicar estas etapas", isOn: $settings.useAdvancedOptions)
                if !settings.useAdvancedOptions {
                    Label("Desativado — as etapas não serão aplicadas.", systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Button("Editar etapas…") { app.route = .advanced(nil) }
                .help("⌘⇧A")
        }
    }

    private func row(_ step: AdvancedStep) -> some View {
        HStack(spacing: 8) {
            Button { app.route = .advanced(step) } label: {
                // Fixed icon column so every step name starts at the same x.
                Label { Text(step.title) } icon: {
                    Image(systemName: step.symbol).frame(width: 18)
                }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Abrir \(step.title)")
            Toggle(step.title, isOn: Binding(
                get: { step.isEnabled(in: settings.advanced) },
                set: { settings = step.applying($0, to: settings) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.vertical, 3)
    }
}
