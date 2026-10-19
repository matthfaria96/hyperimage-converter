import Foundation
import HyperImageCore

enum AppearanceChoice: String, Codable, CaseIterable {
    case system, light, dark
}

enum BrowserLayout: String, Codable, CaseIterable {
    case list, thumbnails
}

/// Everything restored on the next launch.
struct PersistedState: Codable, Equatable {
    var convert = ConvertSettings()
    var appearance = AppearanceChoice.system
    var browserPath = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? NSHomeDirectory()
    var browserLayout = BrowserLayout.list
    var filterName = ImageFileTypes.filters[0].name
    var sort = InputSort()
    var showPreview = true
    var lastAdvancedStep = AdvancedStep.resize
    var resizePresets = StandardSizes.resize

    private static let key = "HyperImage.state.v1"

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: key) else { return PersistedState() }
        return decode(data)
    }

    static func decode(_ data: Data) -> PersistedState {
        (try? TolerantJSON.decode(PersistedState.self, from: data, defaults: PersistedState())) ?? PersistedState()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
