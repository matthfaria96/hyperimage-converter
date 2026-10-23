#if DEBUG
import AppKit
import Foundation
import HyperImageCore

/// Debug-only hooks used to screenshot sheets without UI scripting:
/// HYPERIMAGE_FILES=path:path  HYPERIMAGE_SHEET=advanced|format|preview|progress|rename  HYPERIMAGE_STEP=<AdvancedStep>
/// HYPERIMAGE_OPTIONS=<.hyperoptions file>  HYPERIMAGE_WINDOW=about  HYPERIMAGE_VFOLDER=<name> (first file)
/// HYPERIMAGE_MODE=convert|compress|upscale|rename  HYPERIMAGE_DROP=1: shows the list as if files were being dragged over it.
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
            window.setContentSize(NSSize(width: parts[0], height: parts[1]))
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

    static func apply(to app: AppModel) -> SheetRoute? {
        scheduleSnapshot()
        scheduleResize()
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
        if let mode = env["HYPERIMAGE_MODE"].flatMap(ConvertMode.init(rawValue:)) { app.state.convert.mode = mode }
        if let step = env["HYPERIMAGE_STEP"].flatMap(AdvancedStep.init(rawValue:)) { app.state.lastAdvancedStep = step }
        if let out = env["HYPERIMAGE_OUT"] {
            app.state.convert.useOutputFolder = true
            app.state.convert.outputFolder = out
        }
        switch env["HYPERIMAGE_SHEET"] {
        case "advanced": return .advanced(env["HYPERIMAGE_STEP"].flatMap(AdvancedStep.init(rawValue:)))
        case "format": return .formatSettings
        case "rename": return .renamePreview
        case "preview": return app.inputs.first.map { .conversionPreview($0.url) }
        default: return nil
        }
    }
}
#endif
