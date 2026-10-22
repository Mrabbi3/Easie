import Foundation

/// A minimal XML tree. Element names are stored without their namespace prefix
/// (`a:t` becomes `t`); attributes keep theirs (`r:id`).
final class XMLNode {
    let name: String
    let attributes: [String: String]
    private(set) var children: [XMLNode] = []
    fileprivate(set) var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    subscript(attribute: String) -> String? { attributes[attribute] }

    /// The relationship id attribute (`r:id`), whatever prefix the file uses.
    var relationshipID: String? {
        attributes.first { $0.key.hasSuffix(":id") }?.value
    }

    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XMLNode] { children.filter { $0.name == name } }

    /// All matching elements below this one, in document order, optionally skipping whole subtrees.
    func descendants(_ name: String, skipping skipped: Set<String> = []) -> [XMLNode] {
        var found: [XMLNode] = []
        func visit(_ node: XMLNode) {
            for child in node.children where !skipped.contains(child.name) {
                if child.name == name { found.append(child) }
                visit(child)
            }
        }
        visit(self)
        return found
    }

    static func parse(_ data: Data) throws -> XMLNode {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        private var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            let node = XMLNode(name: elementName, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}

extension String {
    /// Escapes text for XML and drops characters XML 1.0 can't hold.
    var xmlEscaped: String {
        var out = ""
        out.reserveCapacity(utf8.count)
        for scalar in unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
