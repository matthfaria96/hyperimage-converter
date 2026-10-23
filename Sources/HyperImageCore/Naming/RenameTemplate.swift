import Foundation

public enum ExtensionCase: String, Codable, CaseIterable, Sendable {
    case noChange, lower, upper

    public func apply(_ ext: String) -> String {
        switch self {
        case .noChange: ext
        case .lower: ext.lowercased()
        case .upper: ext.uppercased()
        }
    }
}

/// Filename templates: `#` digits of the sequence number, `*` original name, `$P` parent folder,
/// `$Y $M $D $H $N $S` date parts.
public enum RenameTemplate {
    public static func usesSequence(_ template: String) -> Bool { template.contains("#") }

    /// True when the template has a date token, so callers can skip reading each file's date otherwise.
    public static func usesDate(_ template: String) -> Bool {
        template.range(of: #"\$[YMDHNS]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Produces a base name (no extension).
    public static func render(_ template: String, originalURL: URL, number: Int, date: Date) -> String {
        let original = originalURL.deletingPathExtension().lastPathComponent
        let parent = originalURL.deletingLastPathComponent().lastPathComponent
        let parts = TextVariables.dateParts(date)
        let tokens: [(String, String)] = [
            ("$P", parent), ("$Y", parts[1]), ("$M", parts[2]), ("$D", parts[3]),
            ("$H", parts[4]), ("$N", parts[5]), ("$S", parts[6]),
        ]
        var output = ""
        var i = template.startIndex
        while i < template.endIndex {
            let c = template[i]
            if c == "#" {
                var run = 0
                while i < template.endIndex && template[i] == "#" { run += 1; i = template.index(after: i) }
                output += String(format: "%0\(run)d", number)
                continue
            }
            if c == "*" {
                output += original
            } else if c == "$", let (token, value) = tokens.first(where: { template[i...].uppercased().hasPrefix($0.0) }) {
                output += value
                i = template.index(i, offsetBy: token.count)
                continue
            } else {
                output.append(c)
            }
            i = template.index(after: i)
        }
        return sanitized(output)
    }

    /// Removes characters macOS filenames cannot contain.
    static func sanitized(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "_" : cleaned
    }
}

/// Search & replace on the base name (three pairs) and on the extension.
public struct SearchReplaceRule: Codable, Equatable, Sendable {
    public struct Pair: Codable, Equatable, Sendable {
        public var search = ""
        public var replace = ""
        public init(search: String = "", replace: String = "") {
            self.search = search
            self.replace = replace
        }
    }

    public var pairs = [Pair(), Pair(), Pair()]
    public var extensionPair = Pair()
    public var caseSensitive = false

    public init() {}

    public func apply(name: String, ext: String) -> (name: String, ext: String) {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let newName = pairs.filter { !$0.search.isEmpty }.reduce(name) {
            $0.replacingOccurrences(of: $1.search, with: $1.replace, options: options)
        }
        let newExt = extensionPair.search.isEmpty ? ext
            : ext.replacingOccurrences(of: extensionPair.search, with: extensionPair.replace, options: options)
        return (RenameTemplate.sanitized(newName), newExt)
    }
}
