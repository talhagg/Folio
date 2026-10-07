import Foundation

/// HTML ve Confluence "storage" biçimini markdown'a çevirir (başlıklar, paragraflar, listeler, tablolar,
/// kod, alıntı, bağlantılar, görev listeleri). Betik/stil/gezinme içerikleri atlanır.
enum HTMLToMarkdown {
    struct Result: Equatable {
        var title: String?
        var markdown: String
    }

    /// Genel web sayfası. Varsa `<article>`/`<main>` içeriği tercih edilir.
    static func convert(html: String) -> Result {
        let title = html.firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/).map {
            String($0.1).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let cleaned = preClean(html)
        guard let document = try? XMLDocument(xmlString: cleaned, options: [.documentTidyHTML]),
              let root = document.rootElement() else {
            return Result(title: nil, markdown: html)
        }
        let content = root.firstDescendant(named: "article")
            ?? root.firstDescendant(named: "main")
            ?? root.firstDescendant(where: { $0.attribute(named: "id") == "main-content" })
            ?? root.firstDescendant(named: "body")
            ?? root
        return Result(title: title?.isEmpty == true ? nil : title, markdown: render(content))
    }

    /// Confluence storage biçimi (XHTML + `ac:`/`ri:` makroları).
    static func convert(confluenceStorage storage: String) -> String {
        var xml = storage
        // Önekli öğe/öznitelikleri ad alanı bildirimi gerektirmeyen adlara çevir.
        xml = xml.replacingOccurrences(of: #"<(/?)(ac|ri):"#, with: "<$1$2-", options: .regularExpression)
        xml = xml.replacingOccurrences(of: #"\s(ac|ri):([a-zA-Z-]+)="#, with: " $1-$2=", options: .regularExpression)
        xml = replacingNamedEntities(xml)
        guard let document = try? XMLDocument(xmlString: "<root>\(xml)</root>", options: []),
              let root = document.rootElement() else {
            return convert(html: storage).markdown
        }
        return render(root)
    }

    /// macOS'un HTML düzelticisi HTML5 öğelerini (nav, article, main…) tanımaz; etiketi atıp metni bırakır.
    /// Bu yüzden gürültü öğeleri ayrıştırmadan önce silinir ve asıl içerik (`article`/`main`) önceden seçilir.
    private static func preClean(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "nav", "svg", "template", "iframe", "form", "button"] {
            text = text.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*/>", with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
        for tag in ["article", "main"] {
            if let range = text.range(of: "(?is)<\(tag)\\b[^>]*>.*</\(tag)>", options: .regularExpression) {
                let inner = text[range]
                    .replacingOccurrences(of: "(?is)^<\(tag)\\b[^>]*>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "(?is)</\(tag)>$", with: "", options: .regularExpression)
                return "<html><body>\(inner)</body></html>"
            }
        }
        return text
    }

    // MARK: - Dönüştürme

    private static let skipped: Set<String> = ["script", "style", "noscript", "nav", "svg", "form", "iframe", "button", "template", "head"]

    static func render(_ element: XMLElement) -> String {
        blocks(element).joined(separator: "\n\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blocks(_ element: XMLElement) -> [String] {
        var result: [String] = []
        var inlineBuffer = ""

        func flush() {
            let text = inlineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(text) }
            inlineBuffer = ""
        }

        for child in element.children ?? [] {
            guard let child = child as? XMLElement else {
                if child.kind == .text { inlineBuffer += collapse(child.stringValue ?? "") }
                continue
            }
            let name = child.localName ?? child.name ?? ""
            if skipped.contains(name) { continue }
            if let block = block(child, name: name) {
                flush()
                result.append(contentsOf: block)
            } else {
                inlineBuffer += inline(child)
            }
        }
        flush()
        return result
    }

    /// Blok öğe ise markdown blokları; satır içi öğe ise `nil`.
    private static func block(_ element: XMLElement, name: String) -> [String]? {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(name.dropFirst()) ?? 1
            let text = inlineText(element)
            return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]
        case "p":
            let text = inlineText(element)
            return text.isEmpty ? [] : [text]
        case "ul", "ol", "ac-task-list":
            return [list(element, ordered: name == "ol", depth: 0)].filter { !$0.isEmpty }
        case "table":
            return table(element).map { [$0.markdown] } ?? []
        case "pre":
            return ["```\n" + (element.stringValue ?? "").trimmingCharacters(in: .newlines) + "\n```"]
        case "blockquote":
            let inner = render(element)
            return inner.isEmpty ? [] : [inner.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")]
        case "hr":
            return ["---"]
        case "div", "section", "article", "main", "body", "header", "footer", "aside", "figure", "root",
             "html", "tbody", "thead", "ac-rich-text-body", "ac-layout", "ac-layout-section", "ac-layout-cell", "details", "summary":
            return blocks(element)
        case "ac-structured-macro":
            return macro(element)
        case "ac-image", "ac-emoticon", "ac-parameter", "ac-placeholder":
            return []
        default:
            return nil
        }
    }

    private static func macro(_ element: XMLElement) -> [String] {
        let macroName = element.attribute(named: "ac-name") ?? ""
        if ["code", "noformat"].contains(macroName) {
            let language = element.children(named: "ac-parameter").first { $0.attribute(named: "ac-name") == "language" }?.stringValue ?? ""
            let code = element.firstDescendant(named: "ac-plain-text-body")?.stringValue ?? ""
            return ["```\(language)\n" + code.trimmingCharacters(in: .newlines) + "\n```"]
        }
        guard let body = element.firstDescendant(named: "ac-rich-text-body") else { return [] }
        let inner = render(body)
        guard !inner.isEmpty else { return [] }
        if ["info", "note", "warning", "tip", "panel", "expand"].contains(macroName) {
            return [inner.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")]
        }
        return [inner]
    }

    private static func list(_ element: XMLElement, ordered: Bool, depth: Int) -> String {
        var lines: [String] = []
        var number = 1
        let indent = String(repeating: "  ", count: depth)
        for item in element.childElements {
            let name = item.localName ?? ""
            if name == "ac-task" {
                let done = item.firstDescendant(named: "ac-task-status")?.stringValue?.trimmingCharacters(in: .whitespaces) == "complete"
                let text = item.firstDescendant(named: "ac-task-body").map(inlineText) ?? ""
                lines.append("\(indent)- [\(done ? "x" : " ")] \(text)")
                continue
            }
            guard name == "li" else { continue }
            var text = ""
            var nested: [String] = []
            for child in item.children ?? [] {
                if let child = child as? XMLElement, ["ul", "ol"].contains(child.localName ?? "") {
                    nested.append(list(child, ordered: child.localName == "ol", depth: depth + 1))
                } else if let child = child as? XMLElement {
                    text += (child.localName == "p" ? inlineText(child) + " " : inline(child))
                } else {
                    text += collapse(child.stringValue ?? "")
                }
            }
            let marker = ordered ? "\(number)." : "-"
            number += 1
            lines.append(indent + marker + " " + text.trimmingCharacters(in: .whitespaces))
            lines.append(contentsOf: nested.filter { !$0.isEmpty })
        }
        return lines.joined(separator: "\n")
    }

    private static func table(_ element: XMLElement) -> MarkdownTable? {
        let rows = element.descendants(named: "tr").filter { $0.ancestor(named: "table") === element }
        guard !rows.isEmpty else { return nil }
        let cells = rows.map { row in
            row.childElements
                .filter { ["td", "th"].contains($0.localName ?? "") }
                .map { cell in render(cell).replacingOccurrences(of: "\n\n", with: " ").replacingOccurrences(of: "\n", with: " ") }
        }
        let firstIsHeader = rows[0].childElements.contains { $0.localName == "th" }
        if firstIsHeader || cells.count > 1 {
            return MarkdownTable(header: cells[0], rows: Array(cells.dropFirst())).normalized
        }
        return MarkdownTable(header: cells[0].indices.map { String(localized: "Sütun \($0 + 1)") }, rows: cells).normalized
    }

    private static func inlineText(_ element: XMLElement) -> String {
        (element.children ?? []).map { child in
            if let child = child as? XMLElement { return inline(child) }
            return collapse(child.stringValue ?? "")
        }
        .joined()
        .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    }

    private static func inline(_ element: XMLElement) -> String {
        let name = element.localName ?? ""
        if skipped.contains(name) { return "" }
        let content = inlineText(element)
        switch name {
        case "strong", "b":
            return content.isEmpty ? "" : "**\(content)**"
        case "em", "i":
            return content.isEmpty ? "" : "*\(content)*"
        case "code", "tt":
            return content.isEmpty ? "" : "`\(element.stringValue ?? content)`"
        case "br":
            return "\n"
        case "a":
            guard let href = element.attribute(named: "href"), href.hasPrefix("http") else { return content }
            return "[\(content.isEmpty ? href : content)](\(href))"
        case "img":
            guard let src = element.attribute(named: "src"), src.hasPrefix("http") else { return "" }
            return "![\(element.attribute(named: "alt") ?? "")](\(src))"
        case "ac-link":
            let title = element.firstDescendant(named: "ri-page")?.attribute(named: "ri-content-title")
            return content.isEmpty ? (title ?? "") : content
        case "ac-emoticon", "ac-image", "ac-parameter":
            return ""
        default:
            return content
        }
    }

    private static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static let entities: [String: String] = [
        "nbsp": "&#160;", "ndash": "&#8211;", "mdash": "&#8212;", "hellip": "&#8230;", "lsquo": "&#8216;",
        "rsquo": "&#8217;", "ldquo": "&#8220;", "rdquo": "&#8221;", "bull": "&#8226;", "middot": "&#183;",
        "copy": "&#169;", "reg": "&#174;", "trade": "&#8482;", "euro": "&#8364;", "laquo": "&#171;", "raquo": "&#187;",
        "rarr": "&#8594;", "larr": "&#8592;", "times": "&#215;", "deg": "&#176;",
    ]

    /// XML'in tanımadığı HTML varlıklarını sayısal karşılığına çevirir.
    private static func replacingNamedEntities(_ text: String) -> String {
        var result = ""
        var remainder = Substring(text)
        while let match = remainder.firstMatch(of: /&([a-zA-Z]+);/) {
            result += remainder[..<match.range.lowerBound]
            let name = String(match.1)
            if ["amp", "lt", "gt", "quot", "apos"].contains(name) {
                result += remainder[match.range]
            } else {
                result += entities[name] ?? ""
            }
            remainder = remainder[match.range.upperBound...]
        }
        return result + remainder
    }
}

extension XMLElement {
    var childElements: [XMLElement] { (children ?? []).compactMap { $0 as? XMLElement } }

    func children(named name: String) -> [XMLElement] {
        childElements.filter { $0.localName == name || $0.name == name }
    }

    func attribute(named name: String) -> String? {
        if let value = attribute(forName: name)?.stringValue { return value }
        return attributes?.first { $0.localName == name || $0.name == name }?.stringValue
    }

    func firstDescendant(named name: String) -> XMLElement? {
        firstDescendant { $0.localName == name || $0.name == name }
    }

    func firstDescendant(where predicate: (XMLElement) -> Bool) -> XMLElement? {
        for child in childElements {
            if predicate(child) { return child }
            if let found = child.firstDescendant(where: predicate) { return found }
        }
        return nil
    }

    func descendants(named name: String) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in childElements {
            if child.localName == name || child.name == name { result.append(child) }
            result += child.descendants(named: name)
        }
        return result
    }

    func ancestor(named name: String) -> XMLElement? {
        var node = parent as? XMLElement
        while let current = node {
            if current.localName == name || current.name == name { return current }
            node = current.parent as? XMLElement
        }
        return nil
    }
}
