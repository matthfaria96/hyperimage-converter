#if DEBUG
import AppKit
import Foundation
import HyperImageCore

/// Debug-only hooks used to screenshot sheets without UI scripting:
/// HYPERIMAGE_FILES=path:path  HYPERIMAGE_SHEET=advanced|format|rename|preview|progress  HYPERIMAGE_STEP=<AdvancedStep>
/// HYPERIMAGE_OPTIONS=<.hyperoptions file>  HYPERIMAGE_MODE=rename  HYPERIMAGE_WINDOW=about
/// HYPERIMAGE_SNAPSHOT=<dir>: after a few seconds, writes every visible window (sheets included) as PNG and quits.
/// It draws the views itself, so it needs neither Screen Recording nor Accessibility permission.
enum DebugLaunch {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func scheduleSnapshot() {
        guard let dir = env["HYPERIMAGE_SNAPSHOT"] else { return }
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

    static func apply(to app: AppModel) -> SheetRoute? {
        scheduleSnapshot()
        if let files = env["HYPERIMAGE_FILES"] {
            app.add(files.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        if let path = env["HYPERIMAGE_OPTIONS"], let options = try? AdvancedOptions.load(from: URL(fileURLWithPath: path)) {
            app.state.convert.advanced = options
            app.state.convert.useAdvancedOptions = true
        }
        if let step = env["HYPERIMAGE_STEP"].flatMap(AdvancedStep.init(rawValue:)) { app.state.lastAdvancedStep = step }
        if let out = env["HYPERIMAGE_OUT"] {
            app.state.convert.useOutputFolder = true
            app.state.convert.outputFolder = out
        }
        if env["HYPERIMAGE_MODE"] == "rename" { app.state.mode = .rename }
        switch env["HYPERIMAGE_SHEET"] {
        case "advanced": return .advanced
        case "format": return .formatSettings
        case "rename": return .renamePreview
        case "preview": return app.inputs.first.map { .conversionPreview($0.url) }
        default: return nil
        }
    }
}
#endif
