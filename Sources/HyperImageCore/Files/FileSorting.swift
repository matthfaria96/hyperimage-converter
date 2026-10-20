import Foundation

public enum InputSortKey: String, Codable, CaseIterable, Sendable {
    case none, name, size, dateTaken, type
}

public struct InputSort: Codable, Equatable, Sendable {
    public var key = InputSortKey.none
    public var descending = false

    public init(key: InputSortKey = .none, descending: Bool = false) {
        self.key = key
        self.descending = descending
    }

    /// File size through the same cache the sort uses, so repeated sums over a long list stay cheap.
    public static func cachedSize(of url: URL) -> Int64 {
        Int64(SortKeyCache.shared.number(.size, url) { Double(BatchConverter.fileSize(url)) })
    }

    /// Reads the slow sort keys (file size, EXIF date) for many files in parallel and remembers them, so the
    /// real sort that follows never touches the disk. Safe to call from a background task.
    public func prewarm(_ items: [InputItem]) {
        guard key == .size || key == .dateTaken, items.count > 1 else { return }
        DispatchQueue.concurrentPerform(iterations: items.count) { _ = sortValue(items[$0].url) }
    }

    public func sorted(_ items: [InputItem]) -> [InputItem] {
        guard key != .none else { return items }
        let keyed = items.map { ($0, sortValue($0.url)) }
        let ascending = keyed.sorted { a, b in
            switch (a.1, b.1) {
            case let (.text(x), .text(y)): x.localizedStandardCompare(y) == .orderedAscending
            case let (.number(x), .number(y)): x < y
            default: false
            }
        }.map(\.0)
        return descending ? ascending.reversed() : ascending
    }

    private enum Value { case text(String), number(Double) }

    private func sortValue(_ url: URL) -> Value {
        switch key {
        case .none, .name: .text(url.lastPathComponent)
        case .type: .text(url.pathExtension.lowercased() + "/" + url.lastPathComponent)
        case .size: .number(SortKeyCache.shared.number(.size, url) { Double(BatchConverter.fileSize(url)) })
        case .dateTaken: .number(SortKeyCache.shared.number(.dateTaken, url) { BatchConverter.fileDate(url).timeIntervalSince1970 })
        }
    }
}

/// Remembers size and capture-date lookups: sorting a long list then reads each file once per session.
final class SortKeyCache: @unchecked Sendable {
    static let shared = SortKeyCache()
    private let lock = NSLock()
    private var values: [InputSortKey: [URL: Double]] = [:]

    func number(_ key: InputSortKey, _ url: URL, compute: () -> Double) -> Double {
        lock.lock()
        if let hit = values[key]?[url] { lock.unlock(); return hit }
        lock.unlock()
        let value = compute()
        lock.lock()
        values[key, default: [:]][url] = value
        lock.unlock()
        return value
    }
}
