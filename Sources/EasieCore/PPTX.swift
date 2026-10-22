import Foundation

/// The words on one slide: its title, its bullet points (with indent level) and the speaker notes.
struct Slide {
    var title: String
    var points: [(level: Int, text: String)]
    var notes: [String]
}

/// Reads the text of PowerPoint decks (.pptx) directly, with no Office install needed.
enum PPTX {
    static func read(_ url: URL) throws -> [Slide] {
        let zip = try ZipArchive(url: url)
        guard let presentation = try zip.xml("ppt/presentation.xml") else { throw ZipArchive.FormatError() }
        let relationships = try zip.relationships(of: "ppt/presentation.xml")

        return try presentation.descendants("sldId").compactMap { reference in
            guard let id = reference.relationshipID, let path = relationships[id]?.path,
                  let slide = try zip.xml(path) else { return nil }
            var result = parse(slide)
            let notesPath = try zip.relationships(of: path).values.first { $0.type.hasSuffix("/notesSlide") }?.path
            if let notesPath, let notes = try zip.xml(notesPath) {
                result.notes = notes.descendants("sp")
                    .filter { $0.descendants("ph").first?["type"] == "body" }
                    .flatMap { paragraphs(in: $0).map(\.text) }
            }
            return result
        }
    }

    private static func parse(_ slide: XMLNode) -> Slide {
        var title = ""
        var points: [(Int, String)] = []
        for shape in slide.descendants("sp") {
            let placeholder = shape.descendants("ph").first?["type"] ?? ""
            if ["sldNum", "dt", "ftr"].contains(placeholder) { continue }
            let lines = paragraphs(in: shape)
            if ["title", "ctrTitle"].contains(placeholder), title.isEmpty {
                title = lines.map(\.text).joined(separator: " ")
            } else {
                points += lines
            }
        }
        for table in slide.descendants("tbl") {
            for row in table.children("tr") {
                let cells = row.children("tc").map { $0.descendants("t").map(\.text).joined() }
                points.append((0, cells.joined(separator: " | ")))
            }
        }
        return Slide(title: title, points: points, notes: [])
    }

    private static func paragraphs(in shape: XMLNode) -> [(level: Int, text: String)] {
        guard let body = shape.child("txBody") else { return [] }
        return body.children("p").compactMap { paragraph in
            let level = paragraph.child("pPr")?["lvl"].flatMap(Int.init) ?? 0
            let text = paragraph.children.map { piece -> String in
                switch piece.name {
                case "r", "fld": return piece.child("t")?.text ?? ""
                case "br": return "\n"
                default: return ""
                }
            }.joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (level, trimmed)
        }
    }
}

/// Text renderings of a deck.
enum Slides {
    private static func heading(_ slide: Slide, number: Int) -> String {
        slide.title.isEmpty ? "Slide \(number)" : "Slide \(number): \(slide.title)"
    }

    static func html(_ slides: [Slide]) -> String {
        var out = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12pt;line-height:1.4}
        h2{font-size:17pt;margin-top:24pt}.notes{color:#666;font-style:italic}
        </style></head><body>\n
        """
        for (index, slide) in slides.enumerated() {
            out += "<h2>\(Markdown.escape(heading(slide, number: index + 1)))</h2>\n"
            var depth = 0
            for point in slide.points {
                let level = point.level + 1
                while depth < level { out += "<ul>"; depth += 1 }
                while depth > level { out += "</ul>"; depth -= 1 }
                out += "<li>" + Markdown.escape(point.text).replacingOccurrences(of: "\n", with: "<br>") + "</li>\n"
            }
            while depth > 0 { out += "</ul>"; depth -= 1 }
            if !slide.notes.isEmpty {
                out += "<p class=\"notes\">Notes: " + Markdown.escape(slide.notes.joined(separator: " ")) + "</p>\n"
            }
        }
        return out + "</body></html>\n"
    }

    static func markdown(_ slides: [Slide]) -> String {
        slides.enumerated().map { index, slide in
            var block = "## " + heading(slide, number: index + 1)
            if !slide.points.isEmpty {
                block += "\n\n" + slide.points.map {
                    String(repeating: "  ", count: $0.level) + "- " + $0.text.replacingOccurrences(of: "\n", with: " ")
                }.joined(separator: "\n")
            }
            if !slide.notes.isEmpty { block += "\n\n> Notes: " + slide.notes.joined(separator: " ") }
            return block
        }.joined(separator: "\n\n") + "\n"
    }

    static func text(_ slides: [Slide]) -> String {
        slides.enumerated().map { index, slide in
            var lines = [heading(slide, number: index + 1)]
            lines += slide.points.map { String(repeating: "    ", count: $0.level + 1) + "• " + $0.text }
            if !slide.notes.isEmpty { lines.append("    Notes: " + slide.notes.joined(separator: " ")) }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    static func json(_ slides: [Slide]) -> JSONValue {
        .array(slides.enumerated().map { index, slide in
            .object([
                ("slide", .number(String(index + 1))),
                ("title", .string(slide.title)),
                ("text", .array(slide.points.map { .string($0.text) })),
                ("notes", .string(slide.notes.joined(separator: "\n"))),
            ])
        })
    }
}
