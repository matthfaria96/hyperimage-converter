import Foundation

/// A property value from a Delphi binary component stream (the "TPF0" format of `.dfm` and FastStone's `.ccf`).
public enum DelphiValue: Equatable, Sendable {
    case integer(Int)
    case double(Double)
    case string(String)
    case identifier(String)
    case boolean(Bool)
    case set([String])
    case other

    var int: Int? {
        switch self {
        case .integer(let v): v
        case .double(let v): Int(v.rounded())
        case .string(let s): Int(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case .integer(let v): Double(v)
        case .double(let v): v
        // Delphi writes edit-box text with the user's decimal separator.
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }

    var bool: Bool? { if case .boolean(let v) = self { v } else { nil } }

    var text: String? {
        switch self {
        case .string(let s), .identifier(let s): s
        default: nil
        }
    }
}

public enum DelphiStreamError: LocalizedError, Equatable {
    case notAComponentStream
    case truncated
    case unsupportedValue(UInt8)

    public var errorDescription: String? {
        switch self {
        case .notAComponentStream: String(localized: "O arquivo não é um arquivo de opções do FastStone (.ccf).")
        case .truncated: String(localized: "O arquivo de opções está incompleto.")
        case .unsupportedValue(let tag): String(localized: "O arquivo de opções tem um valor desconhecido (tipo \(tag)).")
        }
    }
}

/// Reads the top-level object's properties of a "TPF0" stream. Child objects are not needed for `.ccf`.
public struct DelphiStream {
    public let className: String
    public let properties: [String: DelphiValue]

    public init(data: Data) throws {
        var reader = Reader(bytes: [UInt8](data))
        guard data.starts(with: Array("TPF0".utf8)), try reader.bytes(4) == Array("TPF0".utf8) else { throw DelphiStreamError.notAComponentStream }
        className = try reader.shortString()
        _ = try reader.shortString() // object name
        var properties: [String: DelphiValue] = [:]
        while try reader.peek() != 0 {
            let name = try reader.shortString()
            properties[name] = try reader.value()
        }
        self.properties = properties
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        func peek() throws -> UInt8 {
            guard offset < bytes.count else { throw DelphiStreamError.truncated }
            return bytes[offset]
        }

        mutating func byte() throws -> UInt8 {
            let b = try peek()
            offset += 1
            return b
        }

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= bytes.count else { throw DelphiStreamError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        /// Little-endian signed integer of `count` bytes.
        mutating func integer(_ count: Int) throws -> Int {
            let raw = try bytes(count)
            let unsigned = raw.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let shift = UInt64(64 - count * 8)
            return Int(Int64(bitPattern: unsigned << shift) >> Int64(shift))
        }

        mutating func shortString() throws -> String {
            ansi(try bytes(Int(try byte())))
        }

        func ansi(_ raw: [UInt8]) -> String {
            String(bytes: raw, encoding: .windowsCP1252) ?? String(decoding: raw, as: UTF8.self)
        }

        mutating func value() throws -> DelphiValue {
            let tag = try byte()
            switch tag {
            case 0, 13: return .other                                        // null, nil
            case 2: return .integer(try integer(1))
            case 3: return .integer(try integer(2))
            case 4: return .integer(try integer(4))
            case 19: return .integer(try integer(8))
            case 5: return .double(Self.extended(try bytes(10)))
            case 15: return .double(Double(Float(bitPattern: UInt32(truncatingIfNeeded: try integer(4)))))
            case 6: return .string(try shortString())
            case 7: return .identifier(try shortString())
            case 8: return .boolean(false)
            case 9: return .boolean(true)
            case 12: return .string(ansi(try bytes(try integer(4))))
            case 20: return .string(String(decoding: try bytes(try integer(4)), as: UTF8.self))
            case 18:
                let units = try bytes(try integer(4) * 2)
                let utf16 = stride(from: 0, to: units.count, by: 2).map { UInt16(units[$0]) | UInt16(units[$0 + 1]) << 8 }
                return .string(String(decoding: utf16, as: UTF16.self))
            case 11:
                var members: [String] = []
                while true {
                    let member = try shortString()
                    if member.isEmpty { break }
                    members.append(member)
                }
                return .set(members)
            case 10:
                _ = try bytes(try integer(4))
                return .other
            default:
                throw DelphiStreamError.unsupportedValue(tag)
            }
        }

        /// x87 80-bit extended: sign + 15-bit exponent, then a 64-bit mantissa with an explicit integer bit.
        static func extended(_ b: [UInt8]) -> Double {
            let mantissa = b[0..<8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let signExponent = Int(b[9]) << 8 | Int(b[8])
            let exponent = signExponent & 0x7FFF
            guard mantissa != 0 || exponent != 0 else { return 0 }
            let magnitude = Double(mantissa) / 9_223_372_036_854_775_808.0 * pow(2, Double(exponent - 16383))
            return signExponent & 0x8000 != 0 ? -magnitude : magnitude
        }
    }
}
