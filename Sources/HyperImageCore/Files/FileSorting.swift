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
        case .size: .number(Double(BatchConverter.fileSize(url)))
        case .dateTaken: .number(BatchConverter.fileDate(url).timeIntervalSince1970)
        }
    }
}
