import Foundation
import HyperImageCore

/// Everything restored on the next launch.
struct PersistedState: Codable, Equatable {
    var convert = ConvertSettings()
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

    /// Options that no longer have a switch keep the behaviour the app now always uses.
    func normalized() -> PersistedState {
        var copy = self
        copy.convert.parallel = true
        copy.convert.showErrors = true
        copy.convert.uppercaseExtension = false
        return copy
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
