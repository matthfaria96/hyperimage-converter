#if DEBUG
import AppKit
import Foundation
import ObjectiveC
import HyperImageCore

/// Debug-only hooks used to screenshot sheets without UI scripting:
/// HYPERIMAGE_FILES=path:path  HYPERIMAGE_SHEET=advanced|format|preview|progress  HYPERIMAGE_STEP=<AdvancedStep>
/// HYPERIMAGE_OPTIONS=<.hyperoptions file>  HYPERIMAGE_WINDOW=about  HYPERIMAGE_VFOLDER=<name> (first file)
/// HYPERIMAGE_MODE=convert|compress|upscale  HYPERIMAGE_DROP=1: shows the list as if files were being dragged over it.
/// HYPERIMAGE_SELECT=1 selects the first file (shows the preview card)  HYPERIMAGE_WINDOW_SIZE=<w>x<h> resizes the main window.
/// HYPERIMAGE_SNAPSHOT=<dir>: after a few seconds, writes every visible window (sheets included) as PNG and quits.
/// It draws the views itself, so it needs neither Screen Recording nor Accessibility permission.
enum DebugLaunch {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func scheduleSnapshot() {
        guard let dir = env["HYPERIMAGE_SNAPSHOT"], !dir.isEmpty else { return }
        let delay = Double(env["HYPERIMAGE_SNAPSHOT_DELAY"] ?? "") ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let folder = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window.title.isEmpty ? "window-\(index)" : window.title
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: folder.appendingPathComponent("\(index)-\(name).png"))
            }
            exit(0) // terminate(_:) can be held up by an open sheet
        }
    }

    /// Resizes the main window shortly after launch, so narrow layouts can be captured.
    static func scheduleResize() {
        let parts = env["HYPERIMAGE_WINDOW_SIZE"]?.split(separator: "x").compactMap { Double($0) } ?? []
        guard parts.count == 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) else { return }
            // Larger than the screen sends AppKit and SwiftUI into a resize loop that aborts the app.
            let limit = window.screen?.visibleFrame.size ?? NSSize(width: parts[0], height: parts[1])
            window.setContentSize(NSSize(width: min(parts[0], limit.width), height: min(parts[1], limit.height)))
        }
    }

    /// HYPERIMAGE_APPEARANCE=light|dark forces the appearance for this launch only (nothing is persisted).
    static func applyAppearance() {
        switch env["HYPERIMAGE_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// HYPERIMAGE_FAKE_KEY=1: every window draws as key, without activating the app or taking the focus.
    /// Lets `screencapture -l` record undimmed controls while another app keeps the keyboard focus.
    static func scheduleFakeKey() {
        guard env["HYPERIMAGE_FAKE_KEY"] != nil else { return }
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        let yesWithArgument: @convention(block) (AnyObject, Int) -> Bool = { _, _ in true }
        // Public getters plus the private ones AppKit and SwiftUI consult when they pick the active look.
        let getters: [(cls: AnyClass, name: String)] = [
            (NSWindow.self, "isKeyWindow"), (NSWindow.self, "isMainWindow"), (NSWindow.self, "hasKeyAppearance"),
            (NSWindow.self, "_hasKeyAppearance"), (NSWindow.self, "_hasActiveAppearance"),
            (NSWindow.self, "_hasActiveAppearanceIgnoringKeyFocus"),
            // Never NSApplication.isActive/_isActiveApp: the app then acts as the menu-bar owner and AppKit
            // aborted in -[_NSMenuBarBackingView hitTest:] while the pointer moved over the screen.
        ]
        for target in getters {
            if let method = class_getInstanceMethod(target.cls, NSSelectorFromString(target.name)) {
                method_setImplementation(method, imp_implementationWithBlock(yes))
            }
        }
        let withArgument: [(cls: AnyClass?, name: String)] = [
            (NSWindow.self, "_hasActiveAppearanceForStandardWindowButton:"),
            (NSClassFromString("_NSThemeWidgetCell"), "_hasKeyAppearanceInView:"), // traffic lights
        ]
        for target in withArgument {
            if let cls = target.cls, let method = class_getInstanceMethod(cls, NSSelectorFromString(target.name)) {
                method_setImplementation(method, imp_implementationWithBlock(yesWithArgument))
            }
        }
        for delay in [0.3, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows where window.isVisible {
                    NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: window)
                    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
                    window.contentView?.superview?.needsDisplay = true
                    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                        guard let button = window.standardWindowButton(kind) else { continue }
                        let refresh = NSSelectorFromString("_windowChangedKeyState")
                        if button.responds(to: refresh) { button.perform(refresh) }
                        button.needsDisplay = true
                    }
                }
            }
        }
    }

    static func apply(to app: AppModel) -> SheetRoute? {
        scheduleSnapshot()
        scheduleResize()
        scheduleFakeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { applyAppearance() }
        // Real screenshots need the window key, or every control is drawn dimmed; a second try covers a slow launch.
        if env["HYPERIMAGE_ACTIVATE"] != nil {
            for delay in [0.3, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.isVisible && $0.sheetParent == nil }?.makeKeyAndOrderFront(nil)
                }
            }
        }
        if let files = env["HYPERIMAGE_FILES"] {
            app.add(files.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        if env["HYPERIMAGE_SELECT"] != nil, let first = app.inputs.first { app.selection = [first.url] }
        if let folder = env["HYPERIMAGE_VFOLDER"], let first = app.inputs.first {
            app.move([first.url], toFolder: folder)
        }
        if let path = env["HYPERIMAGE_OPTIONS"], let options = try? AdvancedOptions.load(from: URL(fileURLWithPath: path)) {
            app.state.convert.advanced = options
            app.state.convert.useAdvancedOptions = true
        }
        if env["HYPERIMAGE_EXPAND"] != nil {
            // Every optional row visible at once, for layout screenshots.
            app.state.convert.fullQuality = false
            app.state.convert.keepDimensions = false
            app.state.convert.limitFileSize = true
            app.state.convert.rename = true
            app.state.convert.compressQuality = 64
        }
        if let format = env["HYPERIMAGE_FORMAT"].flatMap(OutputFormat.init(rawValue:)) { app.state.convert.format = format }
        if let mode = env["HYPERIMAGE_MODE"].flatMap(ConvertMode.init(rawValue:)) { app.state.convert.mode = mode }
        if let step = env["HYPERIMAGE_STEP"].flatMap(AdvancedStep.init(rawValue:)) { app.state.lastAdvancedStep = step }
        if let out = env["HYPERIMAGE_OUT"] {
            app.state.convert.useOutputFolder = true
            app.state.convert.outputFolder = out
        }
        switch env["HYPERIMAGE_SHEET"] {
        case "advanced": return .advanced(env["HYPERIMAGE_STEP"].flatMap(AdvancedStep.init(rawValue:)))
        case "format": return .formatSettings
        case "history": return .history
        case "preview": return app.inputs.first.map { .conversionPreview($0.url) }
        default: return nil
        }
    }
}
#endif
