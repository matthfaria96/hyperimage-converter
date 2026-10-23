import HyperImageCore
import SwiftUI

/// The 10 advanced-edit steps, each with its own switch; a step name opens the editor on that step.
struct AdvancedStepsSection: View {
    @Environment(AppModel.self) private var app
    @Binding var settings: ConvertSettings

    var body: some View {
        Section {
            ForEach(AdvancedStep.allCases) { step in
                row(step)
            }
        } header: {
            HStack {
                Text("Edição avançada")
                Spacer()
                Button("Editar etapas…") { app.route = .advanced(nil) }
                    .buttonStyle(.borderless).font(.callout)
                    .help("⌘⇧A")
            }
        } footer: {
            if settings.advanced.hasEnabledStep, !settings.useAdvancedOptions {
                Label("As etapas ligadas não serão aplicadas.", systemImage: "pause.circle").foregroundStyle(.orange)
            } else {
                Text("Redimensionar, cortar, girar, ajustar cores, texto, marca d'água e bordas. Clique no nome para editar.")
            }
        }
        if settings.advanced.hasEnabledStep {
            Section {
                ToggleRow(title: "Aplicar as etapas ligadas", isOn: $settings.useAdvancedOptions)
            }
            .transition(.blurReplace)
        }
    }

    private func row(_ step: AdvancedStep) -> some View {
        Toggle(isOn: Binding(
            get: { step.isEnabled(in: settings.advanced) },
            set: { settings = step.applying($0, to: settings) }
        )) {
            Button { app.route = .advanced(step) } label: {
                HStack(spacing: 6) {
                    // Fixed icon column so every step name starts at the same x.
                    Image(systemName: step.symbol).foregroundStyle(.tint).frame(width: 20)
                    Text(step.title)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Abrir \(step.title)")
        }
    }
}
