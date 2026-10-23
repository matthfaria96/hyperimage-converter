import AppKit
import HyperImageCore
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
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1360, height: 820)
        .commands { AppCommands(model: model) }

        Window("Sobre o HyperImage Converter", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Files opened before the window existed are queued until the model is attached.
    var model: AppModel? {
        didSet {
            guard let model, !pending.isEmpty else { return }
            model.addInBackground(pending)
            pending = []
        }
    }
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.addInBackground(urls) } else { pending += urls }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Finder's "Converter com HyperImage" service (Info.plist NSServices): queues the chosen images and folders.
    @objc func addFilesService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(localized: "Nenhum arquivo recebido.") as NSString
            return
        }
        application(NSApp, open: urls)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // upscayl-bin would otherwise outlive the app and keep the GPU busy.
        ProcessRegistry.shared.terminateAll()
        model?.saveNow()
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Sobre o HyperImage Converter") { openWindow(id: "about") }
        }
        CommandGroup(after: .newItem) {
            Button("Adicionar imagens…") { FilePanels.addFiles(to: model) }
                .keyboardShortcut("o")
                .disabled(model.isBusy)
        }
        CommandMenu("Imagens") {
            Button(model.state.convert.mode.actionTitle) { model.startRequest += 1 }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.inputs.isEmpty || model.isBusy)
            Divider()
            Button("Pré-visualizar") { if let url = model.previewTarget { model.route = .conversionPreview(url) } }
                .keyboardShortcut("y")
                .disabled(model.inputs.isEmpty || model.isBusy || model.state.convert.mode == .upscale)
            Button("Ajustes do formato…") { model.route = .formatSettings }
                .keyboardShortcut(",")
                .disabled(model.isBusy || model.state.convert.mode != .convert)
            Button("Edição avançada…") { model.route = .advanced(nil) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.isBusy || model.state.convert.mode == .upscale)
            Divider()
            Button("Modo Converter") { model.state.convert.mode = .convert }
                .keyboardShortcut("1")
                .disabled(model.isBusy)
            Button("Modo Comprimir") { model.state.convert.mode = .compress }
                .keyboardShortcut("2")
                .disabled(model.isBusy)
            Button("Modo AI Upscale") { model.state.convert.mode = .upscale }
                .keyboardShortcut("3")
                .disabled(model.isBusy)
        }
    }
}
