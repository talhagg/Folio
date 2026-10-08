import Foundation

/// En küçük ZIP yazıcı ("stored" girdiler, CRC-32). Office belgeleri için yeterli.
enum ZipWriter {
    static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var output: [UInt8] = []
        var central: [UInt8] = []
        for file in files {
            let name = Array(file.name.utf8)
            let bytes = [UInt8](file.data)
            let crc = CRC32.checksum(bytes)
            let offset = UInt32(output.count)

            output += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            output += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            output += le16(UInt16(name.count)) + le16(0) + name + bytes

            central += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
            central += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let centralOffset = UInt32(output.count)
        output += central
        output += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(files.count)) + le16(UInt16(files.count))
        output += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        return Data(output)
    }

    private static func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Notu Word belgesine yazar: gerçek başlık stilleri, madde/numaralı listeler ve tablolar.
@MainActor
enum DOCXWriter {
    static func document(for notes: [Note], now: Date) -> Data {
        var body = ""
        var numbering = NumberingState()
        for (index, note) in notes.enumerated() {
            if index > 0 { body += #"<w:p><w:r><w:br w:type="page"/></w:r></w:p>"# }
            body += noteXML(note, now: now, numbering: &numbering)
        }
        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body>
        </w:document>
        """
        return ZipWriter.archive([
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("word/_rels/document.xml.rels", Data(documentRels.utf8)),
            ("word/document.xml", Data(document.utf8)),
            ("word/styles.xml", Data(styles.utf8)),
            ("word/numbering.xml", Data(numbering.xml.utf8)),
        ])
    }

    // MARK: - İçerik

    private static func noteXML(_ note: Note, now: Date, numbering: inout NumberingState) -> String {
        var xml = paragraph(style: "Title", runs(note.title.isEmpty ? String(localized: "Başlıksız not") : note.title))
        var meta: [String] = []
        if let path = note.locationPath { meta.append(path) }
        meta.append(String(localized: "Oluşturuldu \(DateGrouping.editorDateText(for: note.createdAt, now: now))"))
        meta.append(String(localized: "Düzenlendi \(DateGrouping.editorDateText(for: note.updatedAt, now: now))"))
        if let due = note.dueDate { meta.append(String(localized: "Hedef: \(due.formatted(.dateTime.day().month(.abbreviated).year()))")) }
        xml += paragraph(style: "Meta", run(meta.joined(separator: "  ·  ")))

        let tasks = note.sortedTasks
        if !tasks.isEmpty {
            let percent = (note.progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
            xml += paragraph(style: "Heading2", run(String(localized: "Görevler — \(note.status.title), \(note.doneTaskCount)/\(note.taskCount) · \(percent)")))
            for task in tasks {
                xml += paragraph(style: "ListParagraph", run(task.isDone ? "☒ " : "☐ ") + run(task.text, strike: task.isDone))
            }
            xml += paragraph(style: nil, "")
        }

        for parsed in MarkdownDocument.parse(note.body) {
            switch parsed.block {
            case .heading(let level, let text):
                xml += paragraph(style: "Heading\(min(level, 3))", runs(text))
            case .paragraph(let text):
                xml += text.components(separatedBy: "\n").map { paragraph(style: nil, runs($0)) }.joined()
            case .bulletList(let items):
                for item in items {
                    if let checked = item.isChecked {
                        xml += paragraph(style: "ListParagraph", run(checked ? "☒ " : "☐ ") + runs(item.text, strike: checked))
                    } else {
                        xml += paragraph(style: "ListParagraph", numId: NumberingState.bulletID, runs(item.text))
                    }
                }
            case .orderedList(let items):
                let numID = numbering.newOrderedList()
                for item in items {
                    xml += paragraph(style: "ListParagraph", numId: numID, runs(item))
                }
            case .quote(let text):
                xml += paragraph(style: "Quote", runs(text))
            case .code(_, let text):
                xml += text.components(separatedBy: "\n").map { paragraph(style: "Code", run($0)) }.joined()
            case .table(let table):
                xml += tableXML(table.normalized) + paragraph(style: nil, "")
            case .image(let alt, _):
                xml += paragraph(style: "Meta", run(String(localized: "[Görsel: \(alt)]")))
            case .attachment(let name, _):
                xml += paragraph(style: "Meta", run(String(localized: "[Ek: \(name)]")))
            case .rule:
                xml += #"<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="DAD6CE"/></w:pBdr></w:pPr></w:p>"#
            }
        }
        return xml
    }

    private static func tableXML(_ table: MarkdownTable) -> String {
        let border = #"w:val="single" w:sz="4" w:space="0" w:color="DAD6CE""#
        var xml = """
        <w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/>\
        <w:tblBorders><w:top \(border)/><w:left \(border)/><w:bottom \(border)/><w:right \(border)/><w:insideH \(border)/><w:insideV \(border)/></w:tblBorders>\
        <w:tblCellMar><w:top w:w="60" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar>\
        </w:tblPr><w:tblGrid>
        """
        xml += String(repeating: #"<w:gridCol/>"#, count: table.columnCount) + "</w:tblGrid>"
        for (index, row) in ([table.header] + table.rows).enumerated() {
            xml += index == 0 ? #"<w:tr><w:trPr><w:tblHeader/></w:trPr>"# : "<w:tr>"
            for cell in row {
                let shading = index == 0 ? #"<w:shd w:val="clear" w:color="auto" w:fill="F3F1EC"/>"# : ""
                xml += "<w:tc><w:tcPr>\(shading)</w:tcPr>" + paragraph(style: index == 0 ? "TableHeader" : "TableText", runs(cell)) + "</w:tc>"
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>"
    }

    private static func paragraph(style: String?, numId: Int? = nil, _ content: String) -> String {
        var properties = ""
        if let style { properties += #"<w:pStyle w:val="\#(style)"/>"# }
        if let numId { properties += #"<w:numPr><w:ilvl w:val="0"/><w:numId w:val="\#(numId)"/></w:numPr>"# }
        return "<w:p>" + (properties.isEmpty ? "" : "<w:pPr>\(properties)</w:pPr>") + content + "</w:p>"
    }

    /// Satır içi markdown → biçimli run'lar. Bağlantılar "metin (adres)" olarak yazılır.
    private static func runs(_ markdown: String, bold: Bool = false, strike: Bool = false) -> String {
        let parsed = MarkdownBodyView.inline(markdown)
        return parsed.runs.map { item in
            var text = String(parsed[item.range].characters)
            let intent = item.inlinePresentationIntent ?? []
            if let link = item.link, link.absoluteString != text { text += " (\(link.absoluteString))" }
            return run(
                text,
                bold: bold || intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized),
                code: intent.contains(.code),
                strike: strike || intent.contains(.strikethrough)
            )
        }.joined()
    }

    private static func run(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, strike: Bool = false) -> String {
        guard !text.isEmpty else { return "" }
        var properties = ""
        if code { properties += #"<w:rStyle w:val="InlineCode"/>"# }
        if bold { properties += "<w:b/>" }
        if italic { properties += "<w:i/>" }
        if strike { properties += #"<w:strike/><w:color w:val="8F8A81"/>"# }
        let rPr = properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
        return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" }.map(String.init).joined()
    }

    // MARK: - Numaralandırma

    private struct NumberingState {
        static let bulletID = 1
        var orderedIDs: [Int] = []

        /// Her numaralı liste 1'den başlasın diye ayrı bir num örneği.
        mutating func newOrderedList() -> Int {
            let id = 2 + orderedIDs.count
            orderedIDs.append(id)
            return id
        }

        var xml: String {
            var nums = #"<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>"#
            for id in orderedIDs {
                nums += #"<w:num w:numId="\#(id)"><w:abstractNumId w:val="1"/><w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride></w:num>"#
            }
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="567" w:hanging="283"/></w:pPr></w:lvl></w:abstractNum>
            <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="567" w:hanging="340"/></w:pPr></w:lvl></w:abstractNum>
            \(nums)
            </w:numbering>
            """
        }
    }

    // MARK: - Paket dosyaları

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
    </Types>
    """

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
    </Relationships>
    """

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:cs="Georgia"/><w:color w:val="1E1C19"/><w:sz w:val="22"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="140" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="52"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Meta"><w:name w:val="Meta"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="320"/></w:pPr><w:rPr><w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica"/><w:color w:val="57534C"/><w:sz w:val="18"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="200" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="60"/><w:ind w:left="567"/></w:pPr></w:style>
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="567"/><w:pBdr><w:left w:val="single" w:sz="18" w:space="12" w:color="DAD6CE"/></w:pBdr></w:pPr><w:rPr><w:i/><w:color w:val="57534C"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:shd w:val="clear" w:color="auto" w:fill="F3F1EC"/></w:pPr><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/><w:sz w:val="19"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0"/></w:pPr><w:rPr><w:rFonts w:ascii="Helvetica" w:hAnsi="Helvetica"/><w:sz w:val="20"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="TableHeader"><w:name w:val="Table Header"/><w:basedOn w:val="TableText"/><w:rPr><w:b/></w:rPr></w:style>
    <w:style w:type="character" w:styleId="InlineCode"><w:name w:val="Inline Code"/><w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo"/><w:sz w:val="19"/><w:shd w:val="clear" w:color="auto" w:fill="F3F1EC"/></w:rPr></w:style>
    <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="DAD6CE"/><w:left w:val="single" w:sz="4" w:space="0" w:color="DAD6CE"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="DAD6CE"/><w:right w:val="single" w:sz="4" w:space="0" w:color="DAD6CE"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="DAD6CE"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="DAD6CE"/></w:tblBorders></w:tblPr></w:style>
    </w:styles>
    """
}
