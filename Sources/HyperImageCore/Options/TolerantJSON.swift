import Foundation

/// Decodes JSON saved by an older (or newer) build: keys the file lacks take their default values,
/// so adding an option never discards the user's other settings.
public enum TolerantJSON {
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T) throws -> T {
        let stored = try JSONSerialization.jsonObject(with: data)
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
        let merged = try JSONSerialization.data(withJSONObject: merge(base, over: stored))
        return try JSONDecoder().decode(T.self, from: merged)
    }

    /// Stored values win; nested objects merge key by key.
    private static func merge(_ base: Any, over stored: Any) -> Any {
        guard let baseObject = base as? [String: Any], let storedObject = stored as? [String: Any] else { return stored }
        return baseObject.merging(storedObject) { old, new in merge(old, over: new) }
    }
}
