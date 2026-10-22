import Foundation

/// Cleans web pages before Easie reads them, so converting an HTML file can't
/// reach the internet (tracking pixels, remote fonts) or pull in files from
/// elsewhere on the Mac. Text, formatting, tables, links and inline or nearby images are kept.
enum SafeHTML {
    static func sanitize(_ html: String) -> String {
        var s = html
        // Elements that run code, embed other pages, or fetch resources on their own.
        for tag in ["script", "iframe", "object", "embed", "noscript", "template", "svg", "video", "audio"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        for tag in ["script", "iframe", "object", "embed", "link", "meta", "base", "source", "track", "frame", "frameset", "applet"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        // CSS that pulls in other files.
        s = s.replacingOccurrences(of: "@import[^;]*;?", with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "url\\s*\\([^)]*\\)", with: "none", options: [.regularExpression, .caseInsensitive])
        // Inline event handlers (onload=…, onerror=…).
        s = s.replacingOccurrences(of: "\\son[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", with: "", options: [.regularExpression, .caseInsensitive])
        // Resource addresses: only inline data and plain relative paths (no "..", no scheme, no leading "/") survive.
        let attribute = "\\s(src|srcset|background|poster|data|lowsrc|dynsrc|xlink:href)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)"
        guard let regex = try? NSRegularExpression(pattern: attribute, options: .caseInsensitive) else { return s }
        let ns = s as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            var value = ns.substring(with: match.range(at: 2))
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).trimmingCharacters(in: .whitespaces)
            if isSafe(value) { result += ns.substring(with: match.range) }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func isSafe(_ address: String) -> Bool {
        let lower = address.lowercased()
        if lower.hasPrefix("data:image/") { return true }
        if lower.contains(":") || lower.hasPrefix("/") || lower.hasPrefix("\\") || lower.contains("..") || lower.contains("&#") || lower.contains("%2e") {
            return false
        }
        return !lower.isEmpty
    }
}
