import Foundation

/// Helpers for tabular data: CSV/TSV parsing and writing, and table <-> JSON.
enum Tables {
    static func parse(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"", field.isEmpty {
                inQuotes = true
            } else if c == separator {
                row.append(field)
                field = ""
            } else if c.isNewline {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return normalized(rows.filter { $0 != [""] })
    }

    static func delimited(_ rows: [[String]], separator: Character) -> String {
        rows.map { row in
            row.map { cell in
                guard cell.contains(separator) || cell.contains("\"") || cell.contains(where: \.isNewline) else { return cell }
                return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: String(separator))
        }.joined(separator: "\n") + "\n"
    }

    /// Pads every row to the same width.
    static func normalized(_ rows: [[String]]) -> [[String]] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    // MARK: JSON

    /// Interprets JSON as a table: a list of records, a list of rows,
    /// or an object wrapping exactly one such list (e.g. `{"data": [...]}`).
    static func table(from json: JSONValue) -> [[String]]? {
        switch json {
        case .array(let items):
            if items.isEmpty { return [] }
            if items.allSatisfy({ if case .object = $0 { true } else { false } }) {
                var keys: [String] = []
                var seen = Set<String>()
                for case .object(let pairs) in items {
                    for (key, _) in pairs where seen.insert(key).inserted { keys.append(key) }
                }
                let rows: [[String]] = items.map { item in
                    guard case .object(let pairs) = item else { return [] }
                    let lookup = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
                    return keys.map { lookup[$0]?.cellText ?? "" }
                }
                return [keys] + rows
            }
            if items.allSatisfy({ if case .array = $0 { true } else { false } }) {
                return normalized(items.map { item in
                    guard case .array(let cells) = item else { return [] }
                    return cells.map(\.cellText)
                })
            }
            return [["value"]] + items.map { [$0.cellText] }
        case .object(let pairs):
            let lists = pairs.filter { if case .array = $0.1 { true } else { false } }
            if lists.count == 1, let nested = table(from: lists[0].1) { return nested }
            return [pairs.map(\.0), pairs.map(\.1.cellText)]
        default:
            return nil
        }
    }

    /// A header row plus data rows, as a list of JSON records.
    static func records(_ rows: [[String]]) -> JSONValue {
        guard let header = rows.first else { return .array([]) }
        let keys = header.enumerated().map { i, name in name.isEmpty ? "column\(i + 1)" : name }
        return .array(rows.dropFirst().map { row in
            .object(keys.enumerated().map { i, key in (key, JSONValue.inferred(from: i < row.count ? row[i] : "")) })
        })
    }

    // MARK: Text renderings

    /// Sheets with a heading each (when there's more than one).
    static func html(_ sheets: [Sheet]) -> String {
        guard sheets.count > 1 else { return html(sheets.first?.rows ?? []) }
        let tables = sheets.map { sheet in
            "<h2>\(Markdown.escape(sheet.name))</h2>" + tableBody(html(sheet.rows))
        }.joined(separator: "\n")
        return html([] as [[String]]).replacingOccurrences(of: "<table>\n</table>", with: tables)
    }

    private static func tableBody(_ page: String) -> String {
        guard let start = page.range(of: "<table>"), let end = page.range(of: "</table>") else { return "" }
        return String(page[start.lowerBound..<end.upperBound])
    }

    static func markdown(_ sheets: [Sheet]) -> String {
        guard sheets.count > 1 else { return markdown(sheets.first?.rows ?? []) }
        return sheets.map { "## \($0.name)\n\n" + markdown($0.rows) }.joined(separator: "\n")
    }

    static func aligned(_ sheets: [Sheet]) -> String {
        guard sheets.count > 1 else { return aligned(sheets.first?.rows ?? []) }
        return sheets.map { "\($0.name)\n\n" + aligned($0.rows) }.joined(separator: "\n\n")
    }

    static func html(_ rows: [[String]]) -> String {
        func esc(_ s: String) -> String { Markdown.escape(s) }
        var out = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:11pt}
        table{border-collapse:collapse}th,td{border:1px solid #bbb;padding:4px 8px;text-align:left}th{background:#eef}
        </style></head><body><table>\n
        """
        for (i, row) in rows.enumerated() {
            let tag = i == 0 ? "th" : "td"
            out += "<tr>" + row.map { "<\(tag)>\(esc($0))</\(tag)>" }.joined() + "</tr>\n"
        }
        return out + "</table></body></html>\n"
    }

    static func markdown(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        func line(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }.joined(separator: " | ") + " |"
        }
        return ([line(header), line(header.map { _ in "---" })] + rows.dropFirst().map(line)).joined(separator: "\n") + "\n"
    }

    /// Columns padded with spaces so the table reads well in a plain text editor.
    static func aligned(_ rows: [[String]]) -> String {
        let rows = normalized(rows)
        guard let first = rows.first else { return "" }
        let widths = first.indices.map { col in min(40, rows.map { $0[col].count }.max() ?? 0) }
        return rows.map { row in
            row.enumerated().map { col, cell in
                cell.padding(toLength: max(widths[col], cell.count), withPad: " ", startingAt: 0)
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n") + "\n"
    }
}
