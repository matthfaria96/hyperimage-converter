#if DEBUG
import Foundation
import HyperImageCore

/// Debug-only hooks used to screenshot sheets without UI scripting:
/// HYPERIMAGE_FILES=path:path  HYPERIMAGE_SHEET=advanced|format|rename|preview|progress  HYPERIMAGE_STEP=<AdvancedStep>
/// HYPERIMAGE_OPTIONS=<.hyperoptions file>  HYPERIMAGE_MODE=rename
enum DebugLaunch {
    static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func apply(to app: AppModel) -> SheetRoute? {
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
