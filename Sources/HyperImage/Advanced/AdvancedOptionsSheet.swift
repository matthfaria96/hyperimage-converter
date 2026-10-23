import HyperImageCore
import SwiftUI

/// The 10-step editor. Works on a draft; OK commits it. Reopens on the last used step.
struct AdvancedOptionsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var initialStep: AdvancedStep?
    @State private var draft = AdvancedOptions()
    @State private var step: AdvancedStep = .resize
    @State private var presets: [PixelSize] = []
    @State private var sheetAlert: AppAlert?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                Form {
                    Section {
                        Toggle(isOn: enabledBinding) {
                            Label(step.title, systemImage: step.symbol).font(.headline)
                        }
                        .toggleStyle(.switch)
                    }
                    stepForm.disabled(!step.isEnabled(in: draft))
                }
                .formStyle(.grouped)
                .frame(width: 430)
                Divider()
                StepPreview(options: draft, sourceURL: app.selectedItem?.url ?? app.inputs.first?.url)
                    .padding(14)
                    .frame(minWidth: 360)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1000, minHeight: 580)
        .animation(.snappy, value: step)
        .onAppear {
            draft = app.state.convert.advanced
            step = initialStep ?? app.state.lastAdvancedStep
            presets = app.state.resizePresets
        }
        .onChange(of: step) { _, s in app.state.lastAdvancedStep = s }
        .alert(item: $sheetAlert) { Alert(title: Text($0.title), message: Text($0.message)) }
    }

    private var sidebar: some View {
        List(AdvancedStep.allCases, selection: Binding(get: { step }, set: { if let s = $0 { step = s } })) { item in
            Toggle(isOn: Binding(get: { item.isEnabled(in: draft) }, set: { draft = item.setting($0, in: draft) })) {
                Label(item.title, systemImage: item.symbol)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tag(item)
        }
        .listStyle(.sidebar)
        .frame(width: 250)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { step.isEnabled(in: draft) }, set: { draft = step.setting($0, in: draft) })
    }

    @ViewBuilder
    private var stepForm: some View {
        switch step {
        case .resize: ResizeStepView(o: $draft.resize, presets: $presets)
        case .rotate: RotateStepView(o: $draft.rotate)
        case .crop: CropStepView(o: $draft.crop)
        case .canvas: CanvasStepView(o: $draft.canvas)
        case .colorDepth: ColorDepthStepView(o: $draft.colorDepth)
        case .adjustments: AdjustmentsStepView(o: $draft.adjustments)
        case .dpi: DPIStepView(o: $draft.dpi)
        case .text: TextStepView(o: $draft.text)
        case .watermark: WatermarkStepView(o: $draft.watermark)
        case .border: BorderStepView(o: $draft.border)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Desativar Tudo") {
                draft = AdvancedStep.allCases.reduce(draft) { $1.setting(false, in: $0) }
            }
            Button("Carregar…") {
                do {
                    if let loaded = try FilePanels.loadOptions() { draft = loaded }
                } catch {
                    sheetAlert = AppAlert(title: String(localized: "Não foi possível carregar"), message: error.localizedDescription)
                }
            }
            Button("Salvar…") {
                do { try FilePanels.saveOptions(draft) } catch {
                    sheetAlert = AppAlert(title: String(localized: "Não foi possível salvar"), message: error.localizedDescription)
                }
            }
            Spacer()
            Label("A ordem de aplicação segue a lista ao lado.", systemImage: "arrow.down").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button("OK") { commit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .padding(14)
    }

    private func commit() {
        if let message = draft.validationError() {
            sheetAlert = AppAlert(title: String(localized: "Opções avançadas"), message: message)
            return
        }
        app.state.convert.advanced = draft
        app.state.resizePresets = presets
        if draft.hasEnabledStep { app.state.convert.useAdvancedOptions = true }
        dismiss()
    }
}
