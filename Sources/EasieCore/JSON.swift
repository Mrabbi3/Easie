import Foundation

/// A JSON value that keeps object keys in their original order,
/// so converting JSON to CSV (and back) doesn't shuffle the columns.
indirect enum JSONValue {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    /// Turns a spreadsheet cell into the most natural JSON value.
    static func inferred(from cell: String) -> JSONValue {
        switch cell {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default:
            if cell.range(of: #"^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil {
                return .number(cell)
            }
            return .string(cell)
        }
    }

    /// The value as it should appear in a table cell.
    var cellText: String {
        switch self {
        case .null: ""
        case .bool(let b): b ? "true" : "false"
        case .number(let n): n
        case .string(let s): s
        case .array, .object: serialized(pretty: false)
        }
    }

    func serialized(pretty: Bool = true, indent: Int = 0) -> String {
        let pad = pretty ? String(repeating: "  ", count: indent + 1) : ""
        let closePad = pretty ? String(repeating: "  ", count: indent) : ""
        let newline = pretty ? "\n" : ""
        let colon = pretty ? ": " : ":"
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return JSONValue.quote(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let body = items.map { pad + $0.serialized(pretty: pretty, indent: indent + 1) }
            return "[" + newline + body.joined(separator: "," + newline) + newline + closePad + "]"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            let body = pairs.map { pad + JSONValue.quote($0.0) + colon + $0.1.serialized(pretty: pretty, indent: indent + 1) }
            return "{" + newline + body.joined(separator: "," + newline) + newline + closePad + "}"
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
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
        return out + "\""
    }
}

/// A small, order-preserving JSON parser.
struct JSONParser {
    struct SyntaxError: Error {}

    private let bytes: [UInt8]
    private var i = 0
    private var depth = 0
    private static let maxDepth = 512

    static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(data))
        if parser.bytes.starts(with: [0xEF, 0xBB, 0xBF]) { parser.i = 3 }  // UTF-8 BOM
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.i == parser.bytes.count else { throw SyntaxError() }
        return value
    }

    private init(bytes: [UInt8]) { self.bytes = bytes }

    private mutating func value() throws -> JSONValue {
        depth += 1
        defer { depth -= 1 }
        guard depth <= JSONParser.maxDepth else { throw SyntaxError() }
        skipWhitespace()
        guard i < bytes.count else { throw SyntaxError() }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return try number()
        }
    }

    private mutating func object() throws -> JSONValue {
        i += 1
        var pairs: [(String, JSONValue)] = []
        skipWhitespace()
        if peek(UInt8(ascii: "}")) { i += 1; return .object(pairs) }
        while true {
            skipWhitespace()
            guard peek(UInt8(ascii: "\"")) else { throw SyntaxError() }
            let key = try string()
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            pairs.append((key, try value()))
            skipWhitespace()
            if peek(UInt8(ascii: ",")) { i += 1; continue }
            try expect(UInt8(ascii: "}"))
            return .object(pairs)
        }
    }

    private mutating func array() throws -> JSONValue {
        i += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if peek(UInt8(ascii: "]")) { i += 1; return .array(items) }
        while true {
            items.append(try value())
            skipWhitespace()
            if peek(UInt8(ascii: ",")) { i += 1; continue }
            try expect(UInt8(ascii: "]"))
            return .array(items)
        }
    }

    private mutating func string() throws -> String {
        i += 1
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []
        func flushRaw() {
            scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars)
            raw.removeAll()
        }
        while i < bytes.count {
            let c = bytes[i]
            i += 1
            if c == UInt8(ascii: "\"") { flushRaw(); return String(scalars) }
            guard c == UInt8(ascii: "\\") else { raw.append(c); continue }
            flushRaw()
            guard i < bytes.count else { break }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "t"): scalars.append("\t")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "u"):
                var code = try hex4()
                if (0xD800..<0xDC00).contains(code), peek(UInt8(ascii: "\\")), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "u") {
                    i += 2
                    let low = try hex4()
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                }
                scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
            default: scalars.append(Unicode.Scalar(e))
            }
        }
        throw SyntaxError()
    }

    private mutating func hex4() throws -> UInt32 {
        guard i + 4 <= bytes.count, let v = UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16) else {
            throw SyntaxError()
        }
        i += 4
        return v
    }

    private mutating func number() throws -> JSONValue {
        let start = i
        while i < bytes.count, "+-.eE0123456789".utf8.contains(bytes[i]) { i += 1 }
        guard i > start else { throw SyntaxError() }
        return .number(String(decoding: bytes[start..<i], as: UTF8.self))
    }

    private mutating func literal(_ word: String) throws {
        let w = Array(word.utf8)
        guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else { throw SyntaxError() }
        i += w.count
    }

    private mutating func expect(_ c: UInt8) throws {
        guard peek(c) else { throw SyntaxError() }
        i += 1
    }

    private func peek(_ c: UInt8) -> Bool { i < bytes.count && bytes[i] == c }

    private mutating func skipWhitespace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }
}
