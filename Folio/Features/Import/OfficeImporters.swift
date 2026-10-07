import Foundation

/// Excel (.xlsx): her sayfa tablo olarak işlenir (başlık sütunu varsa satır başına not).
enum XLSXImporter {
    static let maxRows = 5_000

    static func documents(from data: Data, fallbackTitle: String) throws -> [ImportedDocument] {
        let archive = try ZipArchive(data: data)
        let sharedStrings = try sharedStrings(archive)
        let sheets = try sheetPaths(archive)
        guard !sheets.isEmpty else { throw ImportError.unreadable("Excel sayfası bulunamadı") }

        var documents: [ImportedDocument] = []
        for (name, path) in sheets {
            guard let xml = try archive.contents(of: path) else { continue }
            let rows = try cells(xml, sharedStrings: sharedStrings)
            guard let header = rows.first else { continue }
            let title = sheets.count == 1 ? fallbackTitle : "\(fallbackTitle) – \(name)"
            documents += TabularImport.documents(header: header, rows: Array(rows.dropFirst()), fallbackTitle: title)
        }
        return documents
    }

    private static func sharedStrings(_ archive: ZipArchive) throws -> [String] {
        guard let data = try archive.contents(of: "xl/sharedStrings.xml"),
              let root = try XMLDocument(data: data).rootElement() else { return [] }
        return root.children(named: "si").map { item in
            item.descendants(named: "t").compactMap(\.stringValue).joined()
        }
    }

    /// (sayfa adı, xl/ içindeki yol) sırasıyla.
    private static func sheetPaths(_ archive: ZipArchive) throws -> [(String, String)] {
        guard let workbookData = try archive.contents(of: "xl/workbook.xml"),
              let workbook = try XMLDocument(data: workbookData).rootElement() else { return [] }
        var targets: [String: String] = [:]
        if let relsData = try archive.contents(of: "xl/_rels/workbook.xml.rels"),
           let rels = try XMLDocument(data: relsData).rootElement() {
            for relationship in rels.descendants(named: "Relationship") {
                if let id = relationship.attribute(named: "Id"), let target = relationship.attribute(named: "Target") {
                    targets[id] = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
                }
            }
        }
        return workbook.descendants(named: "sheet").enumerated().compactMap { index, sheet in
            let name = sheet.attribute(named: "name") ?? String(localized: "Sayfa \(index + 1)")
            let id = sheet.attributes?.first { $0.localName == "id" }?.stringValue
            let path = id.flatMap { targets[$0] } ?? "xl/worksheets/sheet\(index + 1).xml"
            return archive.entries[path] == nil ? nil : (name, path)
        }
    }

    private static func cells(_ data: Data, sharedStrings: [String]) throws -> [[String]] {
        guard let root = try XMLDocument(data: data).rootElement() else { return [] }
        var rows: [[String]] = []
        for row in root.descendants(named: "row").prefix(maxRows + 1) {
            var values: [String] = []
            for cell in row.children(named: "c") {
                let column = cell.attribute(named: "r").flatMap(columnIndex) ?? values.count
                let value: String
                switch cell.attribute(named: "t") {
                case "s":
                    value = Int(cell.firstDescendant(named: "v")?.stringValue ?? "").flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
                case "inlineStr":
                    value = cell.descendants(named: "t").compactMap(\.stringValue).joined()
                case "b":
                    value = cell.firstDescendant(named: "v")?.stringValue == "1" ? "TRUE" : "FALSE"
                default:
                    value = cell.firstDescendant(named: "v")?.stringValue ?? ""
                }
                if column >= values.count { values += Array(repeating: "", count: column - values.count + 1) }
                values[column] = value
            }
            rows.append(values)
        }
        // Sondaki boş sütunları at.
        let width = rows.map { row in (row.lastIndex { !$0.isEmpty } ?? -1) + 1 }.max() ?? 0
        return rows.map { Array($0.prefix(width)) + Array(repeating: "", count: max(0, width - $0.count)) }
    }

    /// "C12" → 2
    static func columnIndex(_ reference: String) -> Int? {
        var index = 0
        var hasLetters = false
        for scalar in reference.unicodeScalars {
            guard (65...90).contains(scalar.value) || (97...122).contains(scalar.value) else { break }
            index = index * 26 + Int((scalar.value & 0xDF) - 64)
            hasLetters = true
        }
        return hasLetters ? index - 1 : nil
    }
}

/// Word (.docx): başlıklar, paragraflar, listeler, kalın/italik ve tablolar.
enum DOCXImporter {
    static func documents(from data: Data, fallbackTitle: String) throws -> [ImportedDocument] {
        let archive = try ZipArchive(data: data)
        guard let xml = try archive.contents(of: "word/document.xml"),
              let root = try XMLDocument(data: xml).rootElement(),
              let body = root.firstDescendant(named: "body") else {
            throw ImportError.unreadable("Word belgesi bulunamadı")
        }

        var blocks: [String] = []
        var title: String?
        for element in body.childElements {
            switch element.localName {
            case "p":
                let text = runs(element)
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let properties = element.firstDescendant(named: "pPr")
                let style = properties?.firstDescendant(named: "pStyle")?.attribute(named: "val") ?? ""
                if let level = headingLevel(style) {
                    if title == nil, level == 1, blocks.isEmpty {
                        title = text
                    } else {
                        blocks.append(String(repeating: "#", count: level) + " " + text)
                    }
                } else if properties?.firstDescendant(named: "numPr") != nil {
                    // Ardışık madde işaretleri tek listede kalsın.
                    if let last = blocks.last, last.hasPrefix("- ") {
                        blocks[blocks.count - 1] = last + "\n- " + text
                    } else {
                        blocks.append("- " + text)
                    }
                } else {
                    blocks.append(text)
                }
            case "tbl":
                let rows = element.children(named: "tr").map { row in
                    row.children(named: "tc").map { cell in
                        cell.descendants(named: "p").map(runs).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    }
                }
                if let header = rows.first {
                    blocks.append(MarkdownTable(header: header, rows: Array(rows.dropFirst())).normalized.markdown)
                }
            default:
                continue
            }
        }
        guard title != nil || !blocks.isEmpty else { throw ImportError.empty }
        return [ImportedDocument(title: title ?? fallbackTitle, markdown: blocks.joined(separator: "\n\n"))]
    }

    /// "Heading2", "Başlık1", "Title" → seviye.
    static func headingLevel(_ style: String) -> Int? {
        let normalized = TabularImport.normalizedKey(style)
        if normalized == "title" || normalized == "konubasligi" { return 1 }
        guard normalized.hasPrefix("heading") || normalized.hasPrefix("baslik") else { return nil }
        let digits = normalized.filter(\.isNumber)
        return Int(digits).map { min(max($0, 1), 6) } ?? 1
    }

    private static func runs(_ paragraph: XMLElement) -> String {
        paragraph.descendants(named: "r").map { run in
            var text = ""
            for child in run.childElements {
                switch child.localName {
                case "t": text += child.stringValue ?? ""
                case "tab": text += "\t"
                case "br", "cr": text += "\n"
                default: break
                }
            }
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
            let properties = run.firstDescendant(named: "rPr")
            func isOn(_ name: String) -> Bool {
                guard let element = properties?.firstDescendant(named: name) else { return false }
                return !["0", "false"].contains(element.attribute(named: "val") ?? "")
            }
            if isOn("b") { text = "**\(text)**" }
            if isOn("i") { text = "*\(text)*" }
            return text
        }
        .joined()
        .replacingOccurrences(of: "****", with: "")
    }
}
