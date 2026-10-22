import Compression
import Foundation

/// Reads entries from a ZIP archive (Office files are ZIPs of XML parts).
struct ZipArchive {
    struct Entry {
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    struct FormatError: Error {}

    private let data: Data
    let entries: [String: Entry]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        entries = try ZipArchive.centralDirectory(of: data)
    }

    /// Largest single part Easie will unpack (guards against "zip bombs").
    static let maxEntrySize = 512 * 1024 * 1024

    func read(_ path: String) throws -> Data? {
        guard let entry = entries[path] else { return nil }
        guard entry.size <= ZipArchive.maxEntrySize, entry.compressedSize <= data.count else { throw FormatError() }
        let header = entry.localHeaderOffset
        guard data.u32(at: header) == 0x0403_4B50 else { throw FormatError() }
        let start = header + 30 + Int(data.u16(at: header + 26)) + Int(data.u16(at: header + 28))
        guard start + entry.compressedSize <= data.count else { throw FormatError() }
        let raw = data.subdata(in: start..<start + entry.compressedSize)
        switch entry.method {
        case 0: return raw
        case 8: return try Deflate.decompress(raw, expectedSize: entry.size)
        default: throw FormatError()
        }
    }

    func xml(_ path: String) throws -> XMLNode? {
        try read(path).map(XMLNode.parse)
    }

    /// The relationships of an Office part, keyed by id, with targets resolved to archive paths.
    func relationships(of part: String) throws -> [String: (type: String, path: String)] {
        let folder = (part as NSString).deletingLastPathComponent
        let relsPath = (folder.isEmpty ? "" : folder + "/") + "_rels/" + (part as NSString).lastPathComponent + ".rels"
        guard let rels = try xml(relsPath) else { return [:] }
        var result: [String: (String, String)] = [:]
        for rel in rels.descendants("Relationship") {
            guard let id = rel["Id"], let target = rel["Target"], rel["TargetMode"] != "External" else { continue }
            result[id] = (rel["Type"] ?? "", ZipArchive.resolve(target, from: folder))
        }
        return result
    }

    static func resolve(_ target: String, from folder: String) -> String {
        var parts = target.hasPrefix("/") ? [] : folder.split(separator: "/").map(String.init)
        for piece in target.split(separator: "/") {
            if piece == ".." { _ = parts.popLast() } else if piece != "." { parts.append(String(piece)) }
        }
        return parts.joined(separator: "/")
    }

    private static func centralDirectory(of data: Data) throws -> [String: Entry] {
        guard data.count >= 22 else { throw FormatError() }
        var end = data.count - 22
        let lowest = max(0, data.count - 22 - 65_535)
        while end >= lowest, data.u32(at: end) != 0x0605_4B50 { end -= 1 }
        guard end >= lowest else { throw FormatError() }

        let count = Int(data.u16(at: end + 10))
        var p = Int(data.u32(at: end + 16))
        guard p < data.count else { throw FormatError() }
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(at: p) == 0x0201_4B50 else { throw FormatError() }
            let nameLength = Int(data.u16(at: p + 28))
            let extraLength = Int(data.u16(at: p + 30))
            let commentLength = Int(data.u16(at: p + 32))
            guard p + 46 + nameLength <= data.count else { throw FormatError() }
            let name = String(decoding: data.subdata(in: p + 46..<p + 46 + nameLength), as: UTF8.self)
            entries[name] = Entry(
                method: data.u16(at: p + 10),
                compressedSize: Int(data.u32(at: p + 20)),
                size: Int(data.u32(at: p + 24)),
                localHeaderOffset: Int(data.u32(at: p + 42))
            )
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }
}

/// Writes a ZIP archive in memory (used to produce XLSX files).
struct ZipWriter {
    private var body = Data()
    private var directory = Data()
    private var count = 0

    mutating func add(_ path: String, _ content: Data) {
        let crc = CRC32.checksum(content)
        var stored = Deflate.compress(content)
        var method: UInt16 = 8
        if stored == nil || stored!.count >= content.count {
            stored = content
            method = 0
        }
        let name = Data(path.utf8)
        let offset = body.count

        body.append(le32: 0x0403_4B50)
        body.append(le16: 20)          // version needed
        body.append(le16: 0x0800)      // UTF-8 names
        body.append(le16: method)
        body.append(le16: 0)           // time
        body.append(le16: 0x21)        // date: 1980-01-01
        body.append(le32: crc)
        body.append(le32: UInt32(stored!.count))
        body.append(le32: UInt32(content.count))
        body.append(le16: UInt16(name.count))
        body.append(le16: 0)
        body.append(name)
        body.append(stored!)

        directory.append(le32: 0x0201_4B50)
        directory.append(le16: 20)
        directory.append(le16: 20)
        directory.append(le16: 0x0800)
        directory.append(le16: method)
        directory.append(le16: 0)
        directory.append(le16: 0x21)
        directory.append(le32: crc)
        directory.append(le32: UInt32(stored!.count))
        directory.append(le32: UInt32(content.count))
        directory.append(le16: UInt16(name.count))
        directory.append(le16: 0)      // extra
        directory.append(le16: 0)      // comment
        directory.append(le16: 0)      // disk
        directory.append(le16: 0)      // internal attributes
        directory.append(le32: 0)      // external attributes
        directory.append(le32: UInt32(offset))
        directory.append(name)
        count += 1
    }

    mutating func add(_ path: String, _ text: String) {
        add(path, Data(text.utf8))
    }

    func finalize() -> Data {
        var out = body
        out.append(directory)
        out.append(le32: 0x0605_4B50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(count))
        out.append(le16: UInt16(count))
        out.append(le32: UInt32(directory.count))
        out.append(le32: UInt32(body.count))
        out.append(le16: 0)
        return out
    }
}

/// Raw DEFLATE, the compression ZIP uses (Apple's COMPRESSION_ZLIB is raw deflate).
enum Deflate {
    static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipArchive.FormatError() }
        return output
    }

    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + data.count / 2 + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}
