import Foundation

/// One named table of cells: a CSV file, or one sheet of a workbook.
struct Sheet {
    var name: String
    var rows: [[String]]
}

/// Reads and writes Excel workbooks (.xlsx) directly, with no Office install needed.
enum XLSX {
    // MARK: Reading

    static func read(_ url: URL) throws -> [Sheet] {
        let zip = try ZipArchive(url: url)
        guard let workbook = try zip.xml("xl/workbook.xml") else { throw ZipArchive.FormatError() }
        let relationships = try zip.relationships(of: "xl/workbook.xml")

        let sharedStrings: [String] = try zip.xml("xl/sharedStrings.xml")?.children("si").map(text(of:)) ?? []
        let dateStyles = dateStyleIndices(try zip.xml("xl/styles.xml"))
        let usesDate1904 = ["1", "true"].contains(workbook.descendants("workbookPr").first?["date1904"] ?? "")

        return try workbook.descendants("sheet").compactMap { sheet in
            guard let id = sheet.relationshipID, let path = relationships[id]?.path,
                  let document = try zip.xml(path) else { return nil }
            let rows = cells(of: document, sharedStrings: sharedStrings, dateStyles: dateStyles, date1904: usesDate1904)
            return Sheet(name: sheet["name"] ?? "Sheet", rows: rows)
        }
    }

    /// Text of a string item, ignoring phonetic guides.
    private static func text(of item: XMLNode) -> String {
        item.descendants("t", skipping: ["rPh"]).map(\.text).joined()
    }

    private static func cells(of sheet: XMLNode, sharedStrings: [String], dateStyles: Set<Int>, date1904: Bool) -> [[String]] {
        var grid: [[String]] = []
        for row in sheet.descendants("row") {
            if let number = row["r"].flatMap(Int.init), number - 1 > grid.count, number - 1 - grid.count < 10_000 {
                grid.append(contentsOf: Array(repeating: [], count: number - 1 - grid.count))
            }
            var values: [String] = []
            for cell in row.children("c") {
                let column = cell["r"].flatMap(columnIndex) ?? values.count
                guard column < 16_384 else { continue }
                if values.count <= column { values.append(contentsOf: Array(repeating: "", count: column + 1 - values.count)) }
                values[column] = value(of: cell, sharedStrings: sharedStrings, dateStyles: dateStyles, date1904: date1904)
            }
            grid.append(values)
        }
        return trimmed(grid)
    }

    private static func value(of cell: XMLNode, sharedStrings: [String], dateStyles: Set<Int>, date1904: Bool) -> String {
        let raw = cell.child("v")?.text ?? ""
        switch cell["t"] ?? "n" {
        case "s": return Int(raw).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
        case "inlineStr": return cell.child("is").map(text(of:)) ?? ""
        case "b": return raw == "1" ? "TRUE" : "FALSE"
        case "str", "e", "d": return raw
        default:
            if let style = cell["s"].flatMap(Int.init), dateStyles.contains(style), let serial = Double(raw) {
                return formatDate(serial: serial, date1904: date1904)
            }
            return raw
        }
    }

    /// "C12" → 2
    private static func columnIndex(_ reference: String) -> Int? {
        var index = 0
        var sawLetter = false
        for scalar in reference.unicodeScalars.prefix(4) {  // Excel stops at XFD; more letters is garbage
            guard (65...90).contains(scalar.value) || (97...122).contains(scalar.value) else { break }
            index = index * 26 + Int(scalar.value & 0x1F)
            sawLetter = true
        }
        return sawLetter ? index - 1 : nil
    }

    /// Drops empty rows and columns at the end, and pads rows to the same width.
    private static func trimmed(_ grid: [[String]]) -> [[String]] {
        var rows = grid
        while let last = rows.last, last.allSatisfy(\.isEmpty) { rows.removeLast() }
        let width = rows.map { row in (row.lastIndex { !$0.isEmpty } ?? -1) + 1 }.max() ?? 0
        return rows.map { row in
            let cut = Array(row.prefix(width))
            return cut + Array(repeating: "", count: width - cut.count)
        }
    }

    // MARK: Dates

    /// Indices of cell styles whose number format shows a date or time.
    private static func dateStyleIndices(_ styles: XMLNode?) -> Set<Int> {
        guard let styles else { return [] }
        var custom: [Int: String] = [:]
        for format in styles.child("numFmts")?.children("numFmt") ?? [] {
            if let id = format["numFmtId"].flatMap(Int.init) { custom[id] = format["formatCode"] ?? "" }
        }
        let builtIn: Set<Int> = Set(14...22).union(27...36).union(45...47).union(50...58)
        let formats = styles.child("cellXfs")?.children("xf") ?? []
        return Set(formats.indices.filter { index in
            let id = formats[index]["numFmtId"].flatMap(Int.init) ?? 0
            if let code = custom[id] { return looksLikeDate(code) }
            return builtIn.contains(id)
        })
    }

    private static func looksLikeDate(_ code: String) -> Bool {
        let stripped = code
            .replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\."#, with: "", options: .regularExpression)
            .lowercased()
        return stripped.contains { "ydhs".contains($0) }
    }

    private static func formatDate(serial: Double, date1904: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let base = calendar.date(from: DateComponents(year: date1904 ? 1904 : 1899, month: date1904 ? 1 : 12, day: date1904 ? 1 : 30))!
        let date = base.addingTimeInterval((serial * 86_400).rounded())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        let hasTime = serial.truncatingRemainder(dividingBy: 1) != 0
        formatter.dateFormat = serial < 1 ? "HH:mm:ss" : hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: Writing

    static func write(_ sheets: [Sheet]) -> Data {
        let names = sheetNames(sheets.map(\.name))
        var zip = ZipWriter()

        let overrides = sheets.indices.map {
            #"<Override PartName="/xl/worksheets/sheet\#($0 + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
        \(overrides)</Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """)

        let sheetEntries = names.enumerated().map { i, name in
            #"<sheet name="\#(name.xmlEscaped)" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
        }.joined()
        zip.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets>\(sheetEntries)</sheets></workbook>
        """)

        let sheetRelationships = sheets.indices.map {
            #"<Relationship Id="rId\#($0 + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#($0 + 1).xml"/>"#
        }.joined()
        zip.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(sheetRelationships)\
        <Relationship Id="rId\(sheets.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        </Relationships>
        """)

        // Style 0: normal. Style 1: bold, for the header row.
        zip.add("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <fonts count="2"><font><sz val="12"/><name val="Calibri"/></font><font><b/><sz val="12"/><name val="Calibri"/></font></fonts>\
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
        <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>\
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
        </styleSheet>
        """)

        for (index, sheet) in sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(index + 1).xml", worksheet(sheet.rows))
        }
        return zip.finalize()
    }

    private static func worksheet(_ rows: [[String]]) -> String {
        let hasHeader = rows.count > 1
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        if hasHeader {
            xml += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>"#
        }
        let width = rows.map(\.count).max() ?? 0
        if width > 0 {
            xml += "<cols>"
            for column in 0..<width {
                let longest = rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
                xml += #"<col min="\#(column + 1)" max="\#(column + 1)" width="\#(min(60, max(8, longest + 2)))" customWidth="1"/>"#
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for (r, row) in rows.enumerated() {
            xml += #"<row r="\#(r + 1)">"#
            for (c, value) in row.enumerated() where !value.isEmpty {
                let reference = columnName(c) + String(r + 1)
                let style = hasHeader && r == 0 ? #" s="1""# : ""
                if case .number = JSONValue.inferred(from: value), !(hasHeader && r == 0) {
                    xml += #"<c r="\#(reference)"\#(style)><v>\#(value)</v></c>"#
                } else {
                    xml += #"<c r="\#(reference)"\#(style) t="inlineStr"><is><t xml:space="preserve">\#(value.xmlEscaped)</t></is></c>"#
                }
            }
            xml += "</row>"
        }
        return xml + "</sheetData></worksheet>"
    }

    /// 0 → "A", 26 → "AA"
    private static func columnName(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let remainder = (n - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// Excel sheet names: at most 31 characters, no []:*?/\ and unique.
    private static func sheetNames(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.enumerated().map { index, raw in
            var base = String(raw.filter { !"[]:*?/\\".contains($0) }.prefix(31)).trimmingCharacters(in: .whitespaces)
            if base.isEmpty { base = "Sheet\(index + 1)" }
            var name = base
            var counter = 2
            while used.contains(name.lowercased()) {
                let suffix = " (\(counter))"
                name = String(base.prefix(31 - suffix.count)) + suffix
                counter += 1
            }
            used.insert(name.lowercased())
            return name
        }
    }
}
