import Foundation
import HyperImageCore

enum AppearanceChoice: String, Codable, CaseIterable {
    case system, light, dark
}

/// Everything restored on the next launch.
struct PersistedState: Codable, Equatable {
    var convert = ConvertSettings()
    var appearance = AppearanceChoice.system
    var sort = InputSort()
    var showPreview = true
    var lastAdvancedStep = AdvancedStep.resize
    var resizePresets = StandardSizes.resize
    var renameTemplates = StandardSizes.renameTemplates

    private static let key = "HyperImage.state.v1"

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: key) else { return PersistedState() }
        return decode(data)
    }

    static func decode(_ data: Data) -> PersistedState {
        let decoded = (try? TolerantJSON.decode(PersistedState.self, from: data, defaults: PersistedState())) ?? PersistedState()
        return decoded.normalized()
    }

    /// Hook for fixing up values a stored state may hold; nothing needs it at the moment.
    func normalized() -> PersistedState { self }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
