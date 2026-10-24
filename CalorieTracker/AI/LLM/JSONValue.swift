import Foundation

/// A JSON value whose objects keep their key order. Request bodies are built from this so that schemas
/// reach the provider with properties in the order we wrote them (models fill them in that order, so
/// `analysis` comes before the numbers).
enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([Member])

    struct Member: Sendable, Equatable {
        let key: String
        let value: JSONValue
    }

    /// Value for `key` in an object, else nil.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// Returns a copy of an object with `key` set (replacing an existing value in place) or appended.
    func setting(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var members) = self else { return self }
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index] = Member(key: key, value: value)
        } else {
            members.append(Member(key: key, value: value))
        }
        return .object(members)
    }

    /// Returns a copy of an object without `key`.
    func removing(_ key: String) -> JSONValue {
        guard case .object(let members) = self else { return self }
        return .object(members.filter { $0.key != key })
    }

    func serialized() -> Data {
        var out = ""
        write(into: &out)
        return Data(out.utf8)
    }

    private func write(into out: inout String) {
        switch self {
        case .string(let value): Self.writeString(value, into: &out)
        case .number(let value): out += Self.format(value)
        case .bool(let value): out += value ? "true" : "false"
        case .null: out += "null"
        case .array(let values):
            out += "["
            for (index, value) in values.enumerated() {
                if index > 0 { out += "," }
                value.write(into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (index, member) in members.enumerated() {
                if index > 0 { out += "," }
                Self.writeString(member.key, into: &out)
                out += ":"
                member.value.write(into: &out)
            }
            out += "}"
        }
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        // Base64 image data is most of a request body and never needs escaping.
        if !value.utf8.contains(where: { $0 < 0x20 || $0 == UInt8(ascii: "\"") || $0 == UInt8(ascii: "\\") }) {
            out += value
        } else {
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
                default: out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    /// Dictionary literals keep their written order.
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(elements.map { Member(key: $0.0, value: $0.1) })
    }
}
