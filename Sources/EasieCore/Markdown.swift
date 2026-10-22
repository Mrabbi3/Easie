import AppKit

/// Just enough Markdown to round-trip everyday notes and READMEs.
enum Markdown {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: Markdown -> HTML

    static func html(from markdown: String) -> String {
        var out: [String] = []
        var paragraph: [String] = []
        var list: String?
        var code: [String]?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            out.append("<p>" + inline(paragraph.joined(separator: " ")) + "</p>")
            paragraph = []
        }
        func closeList() {
            if let tag = list { out.append("</\(tag)>") }
            list = nil
        }
        func listItem(_ text: String, tag: String) {
            flushParagraph()
            if list != tag { closeList(); out.append("<\(tag)>"); list = tag }
            out.append("<li>" + inline(text) + "</li>")
        }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let block = code {
                    out.append("<pre><code>" + escape(block.joined(separator: "\n")) + "</code></pre>")
                    code = nil
                } else {
                    flushParagraph(); closeList()
                    code = []
                }
                continue
            }
            if code != nil { code?.append(line); continue }
            if trimmed.isEmpty { flushParagraph(); closeList(); continue }

            if let match = trimmed.firstMatch(of: #/^(#{1,6})\s+(.*?)\s*#*$/#) {
                flushParagraph(); closeList()
                let level = match.1.count
                out.append("<h\(level)>" + inline(String(match.2)) + "</h\(level)>")
            } else if ["---", "***", "___"].contains(trimmed) {
                flushParagraph(); closeList()
                out.append("<hr>")
            } else if trimmed.hasPrefix(">") {
                flushParagraph(); closeList()
                out.append("<blockquote>" + inline(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) + "</blockquote>")
            } else if let match = trimmed.firstMatch(of: #/^[-*+]\s+(.*)$/#) {
                listItem(String(match.1), tag: "ul")
            } else if let match = trimmed.firstMatch(of: #/^\d+[.)]\s+(.*)$/#) {
                listItem(String(match.1), tag: "ol")
            } else {
                closeList()
                paragraph.append(trimmed)
            }
        }
        if let block = code { out.append("<pre><code>" + escape(block.joined(separator: "\n")) + "</code></pre>") }
        flushParagraph()
        closeList()

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        body{font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12pt;line-height:1.4}
        code,pre{font-family:Menlo,monospace;font-size:10.5pt}pre{background:#f4f4f6;padding:8px}
        blockquote{color:#555;border-left:3px solid #ccc;padding-left:10px}
        </style></head><body>
        \(out.joined(separator: "\n"))
        </body></html>
        """
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        let rules: [(String, String)] = [
            (#"`([^`]+)`"#, "<code>$1</code>"),
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>"),
            (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
            (#"__(.+?)__"#, "<strong>$1</strong>"),
            (#"\*(.+?)\*"#, "<em>$1</em>"),
            (#"(?<![A-Za-z0-9])_(.+?)_(?![A-Za-z0-9])"#, "<em>$1</em>"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }

    // MARK: Rich text -> Markdown

    static func markdown(from text: NSAttributedString) -> String {
        let full = NSRange(location: 0, length: text.length)
        var sizes: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            if let font = value as? NSFont { sizes[font.pointSize, default: 0] += range.length }
        }
        let bodySize = sizes.max { $0.value < $1.value }?.key ?? 12

        var blocks: [(text: String, isListItem: Bool)] = []
        (text.string as NSString).enumerateSubstrings(in: full, options: .byParagraphs) { _, range, _, _ in
            guard range.length > 0 else { return }
            let para = text.attributedSubstring(from: range)
            guard !para.string.trimmingCharacters(in: .whitespaces).isEmpty else { return }

            var largest: CGFloat = 0
            var allBold = true
            para.enumerateAttribute(.font, in: NSRange(location: 0, length: para.length)) { value, r, _ in
                guard let font = value as? NSFont else { return }
                let chunk = (para.string as NSString).substring(with: r)
                guard !chunk.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                largest = max(largest, font.pointSize)
                if !font.fontDescriptor.symbolicTraits.contains(.bold) { allBold = false }
            }
            let heading: String =
                largest >= bodySize * 1.6 ? "# " :
                largest >= bodySize * 1.3 ? "## " :
                largest >= bodySize * 1.12 && allBold ? "### " : ""

            var line = heading.isEmpty ? styledRuns(para) : para.string
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)

            let style = para.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            // Lists keep their markers as text ("•\tItem"), and PDFs only have the text, so look at both.
            let hasMarker = line.firstMatch(of: #/^([•◦▪●○■–]|\d+[.)]?)\t|^[•◦▪●○■]\s/#) != nil
            let isList = hasMarker || !(style?.textLists.isEmpty ?? true)
            if isList {
                let ordered = line.firstMatch(of: #/^\d+/#) != nil
                line = line.replacing(#/^\s*([•◦▪●○■\-–]|\d+[.)]?)\s+/#, with: "")
                line = (ordered ? "1. " : "- ") + line
            }
            blocks.append((heading + line, isList))
        }

        var out = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 { out += block.isListItem && blocks[i - 1].isListItem ? "\n" : "\n\n" }
            out += block.text
        }
        return out + "\n"
    }

    /// Wraps bold, italic and linked runs in Markdown markers.
    private static func styledRuns(_ para: NSAttributedString) -> String {
        struct Style: Equatable { var bold = false, italic = false, link: String? }
        var segments: [(Style, String)] = []
        para.enumerateAttributes(in: NSRange(location: 0, length: para.length)) { attrs, range, _ in
            var style = Style()
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                style.bold = traits.contains(.bold)
                style.italic = traits.contains(.italic)
            }
            if let link = attrs[.link] { style.link = (link as? URL)?.absoluteString ?? (link as? String) }
            let chunk = (para.string as NSString).substring(with: range)
            if let last = segments.last, last.0 == style {
                segments[segments.count - 1].1 += chunk
            } else {
                segments.append((style, chunk))
            }
        }
        return segments.map { style, chunk in
            let core = chunk.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return chunk }
            let lead = chunk.prefix(while: { $0 == " " || $0 == "\t" })
            let trail = String(chunk.reversed().prefix(while: { $0 == " " || $0 == "\t" }))
            var s = core
            if style.italic { s = "*\(s)*" }
            if style.bold { s = "**\(s)**" }
            if let link = style.link { s = "[\(s)](\(link))" }
            return lead + s + trail
        }.joined()
    }
}
