import AppKit
import SwiftUI

@main
struct HyperImageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("HyperImage Converter", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 640)
                .onAppear {
                    delegate.model = model
                    applyAppearance(model.state.appearance)
                }
                .onChange(of: model.state.appearance) { _, choice in applyAppearance(choice) }
        }
        .defaultSize(width: 1360, height: 820)
        .commands { AppCommands(model: model) }
    }

    private func applyAppearance(_ choice: AppearanceChoice) {
        NSApp.appearance = switch choice {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files opened before the window existed are queued until the model is attached.
    var model: AppModel? {
        didSet {
            guard let model, !pending.isEmpty else { return }
            model.add(pending)
            pending = []
        }
    }
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.add(urls) } else { pending += urls }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.saveNow()
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Adicionar Arquivos…") { FilePanels.addFiles(to: model) }
                .keyboardShortcut("o")
        }
        CommandMenu("Aparência") {
            Picker("Aparência", selection: Binding(get: { model.state.appearance }, set: { model.state.appearance = $0 })) {
                Text("Automática").tag(AppearanceChoice.system)
                Text("Clara").tag(AppearanceChoice.light)
                Text("Escura").tag(AppearanceChoice.dark)
            }
            .pickerStyle(.inline)
        }
    }
}
