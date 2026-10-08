import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, docx, markdown, json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: String(localized: "PDF")
        case .docx: String(localized: "Word (.docx)")
        case .markdown: String(localized: "Markdown")
        case .json: String(localized: "JSON")
        }
    }

    var symbolName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .docx: "doc.text"
        case .markdown: "text.alignleft"
        case .json: "curlybraces"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .docx: "docx"
        case .markdown: "md"
        case .json: "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .docx: UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .json: .json
        }
    }
}

/// `fileExporter` için hazır veri.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = ExportFormat.allCases.map(\.contentType)

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Folio JSON yedeği; `JSONImporter` bunu tanır ve görevleriyle geri yükler.
struct FolioExport: Codable, Equatable {
    static let appName = "Folio"

    struct ExportedTask: Codable, Equatable {
        var text: String
        var isDone: Bool
        var dueDate: Date?
    }

    struct ExportedTable: Codable, Equatable {
        var header: [String]
        var rows: [[String]]
    }

    struct ExportedNote: Codable, Equatable {
        var title: String
        var body: String
        /// Gövdedeki tablolar ayrıca yapılandırılmış halde (gövdede de markdown olarak bulunur).
        var tables: [ExportedTable]?
        var notebook: String?
        var section: String?
        var createdAt: Date
        var updatedAt: Date
        var dueDate: Date?
        var isPinned: Bool
        var status: String
        var tasks: [ExportedTask]
    }

    var app = appName
    var version = 1
    var exportedAt: Date
    var notes: [ExportedNote]

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
enum NoteExporter {
    static func data(for notes: [Note], format: ExportFormat, now: Date = .now) throws -> Data {
        switch format {
        case .json: return try json(for: notes, now: now)
        case .markdown: return Data(notes.map(markdown(for:)).joined(separator: "\n\n---\n\n").utf8)
        case .pdf: return pdf(attributedString(for: notes, forWord: false, now: now))
        // AppKit'in Word yazıcısı tabloları düz paragrafa çeviriyor; belge elle yazılır.
        case .docx: return DOCXWriter.document(for: notes, now: now)
        }
    }

    static func suggestedFileName(for notes: [Note], fallback: String) -> String {
        let raw = notes.count == 1 ? notes[0].title : fallback
        let cleaned = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "Not") : cleaned
    }

    // MARK: - JSON

    static func json(for notes: [Note], now: Date) throws -> Data {
        let export = FolioExport(exportedAt: now, notes: notes.map { note in
            FolioExport.ExportedNote(
                title: note.title,
                body: note.body,
                tables: MarkdownDocument.parse(note.body).compactMap { parsed -> FolioExport.ExportedTable? in
                    guard case .table(let table) = parsed.block else { return nil }
                    let normalized = table.normalized
                    return FolioExport.ExportedTable(header: normalized.header, rows: normalized.rows)
                },
                notebook: note.notebook?.name,
                section: note.section?.name,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                dueDate: note.dueDate,
                isPinned: note.isPinned,
                status: note.status.rawValue,
                tasks: note.sortedTasks.map { .init(text: $0.text, isDone: $0.isDone, dueDate: $0.dueDate) }
            )
        })
        return try FolioExport.encoder.encode(export)
    }

    // MARK: - Markdown

    static func markdown(for note: Note) -> String {
        var parts = ["# " + (note.title.isEmpty ? String(localized: "Başlıksız not") : note.title)]
        let tasks = note.sortedTasks
        if !tasks.isEmpty {
            parts.append(tasks.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }.joined(separator: "\n"))
        }
        // Ek referansları başka bir uygulamada anlamsız; adlarıyla yazılır.
        let body = note.body
            .replacing(/!\[([^\]]*)\]\(attachment:[0-9A-Fa-f-]{36}\)/) { "[Görsel: \($0.1)]" }
            .replacing(/\[([^\]]+)\]\(attachment:[0-9A-Fa-f-]{36}\)/) { "[Ek: \($0.1)]" }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Biçimli metin (PDF ve Word ortak)

    private struct Fonts {
        let forWord: Bool

        /// Word'de her sistemde bulunan Georgia; PDF'de New York (gömülür).
        func serif(_ size: CGFloat, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
            var font: NSFont
            if forWord {
                font = NSFont(name: weight == .regular ? "Georgia" : "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: weight)
            } else {
                let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)
                font = descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size, weight: weight)
            }
            if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            return font
        }

        func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            forWord ? (NSFont(name: weight == .regular ? "Helvetica" : "Helvetica-Bold", size: size) ?? .systemFont(ofSize: size, weight: weight))
                : .systemFont(ofSize: size, weight: weight)
        }

        func mono(_ size: CGFloat) -> NSFont {
            forWord ? (NSFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular))
                : .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    // Kağıt üzerinde her zaman açık tema renkleri.
    private static let ink = NSColor.hex(0x1E1C19)
    private static let secondary = NSColor.hex(0x57534C)
    private static let tertiary = NSColor.hex(0x8F8A81)
    private static let rule = NSColor.hex(0xDAD6CE)
    private static let shade = NSColor.hex(0xF3F1EC)

    static func attributedString(for notes: [Note], forWord: Bool, now: Date = .now) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, note) in notes.enumerated() {
            if index > 0 {
                // Notlar arasında sayfa sonu.
                result.append(NSAttributedString(string: "\u{0C}"))
            }
            result.append(attributedString(for: note, forWord: forWord, now: now))
        }
        return result
    }

    static func attributedString(for note: Note, forWord: Bool, now: Date = .now) -> NSAttributedString {
        let fonts = Fonts(forWord: forWord)
        let output = NSMutableAttributedString()

        func paragraph(spacingBefore: CGFloat = 0, after: CGFloat = 8, indent: CGFloat = 0, lineSpacing: CGFloat = 3) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = spacingBefore
            style.paragraphSpacing = after
            style.lineSpacing = lineSpacing
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            return style
        }

        func add(_ text: String, font: NSFont, color: NSColor = ink, style: NSParagraphStyle) {
            output.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }

        func addInline(_ text: String, font: NSFont, color: NSColor = ink, style: NSParagraphStyle, prefix: String = "") {
            let line = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: secondary, .paragraphStyle: style])
            line.append(inline(text, font: font, color: color, fonts: fonts, style: style))
            line.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: style]))
            output.append(line)
        }

        // Başlık ve bilgi satırı
        add(note.title.isEmpty ? String(localized: "Başlıksız not") : note.title, font: fonts.serif(26, weight: .semibold), style: paragraph(after: 6))
        var meta: [String] = []
        if let path = note.locationPath { meta.append(path) }
        meta.append(String(localized: "Oluşturuldu \(DateGrouping.editorDateText(for: note.createdAt, now: now))"))
        meta.append(String(localized: "Düzenlendi \(DateGrouping.editorDateText(for: note.updatedAt, now: now))"))
        if let due = note.dueDate { meta.append(String(localized: "Hedef: \(due.formatted(.dateTime.day().month(.abbreviated).year()))")) }
        add(meta.joined(separator: "  ·  "), font: fonts.sans(10), color: secondary, style: paragraph(after: 16))

        // Görevler
        let tasks = note.sortedTasks
        if !tasks.isEmpty {
            let percent = (note.progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
            add(String(localized: "Görevler — \(note.status.title), \(note.doneTaskCount)/\(note.taskCount) · \(percent)"),
                font: fonts.serif(15, weight: .semibold), style: paragraph(spacingBefore: 4, after: 6))
            for task in tasks {
                let line = NSMutableAttributedString(string: task.isDone ? "☑︎  " : "☐  ", attributes: [.font: fonts.sans(12), .foregroundColor: task.isDone ? secondary : ink])
                var attributes: [NSAttributedString.Key: Any] = [.font: fonts.serif(12), .foregroundColor: task.isDone ? tertiary : ink]
                if task.isDone { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                line.append(NSAttributedString(string: task.text, attributes: attributes))
                line.append(NSAttributedString(string: "\n"))
                line.addAttribute(.paragraphStyle, value: paragraph(after: 3, indent: 4), range: NSRange(location: 0, length: line.length))
                output.append(line)
            }
            add("", font: fonts.serif(6), style: paragraph(after: 6))
        }

        // Gövde
        for parsed in MarkdownDocument.parse(note.body) {
            switch parsed.block {
            case .heading(let level, let text):
                let size: CGFloat = level == 1 ? 20 : level == 2 ? 17 : 14
                addInline(text, font: fonts.serif(size, weight: .semibold), style: paragraph(spacingBefore: 10, after: 6))
            case .paragraph(let text):
                addInline(text, font: fonts.serif(12), style: paragraph(after: 9))
            case .bulletList(let items):
                for item in items {
                    let marker = item.isChecked.map { $0 ? "☑︎  " : "☐  " } ?? "•  "
                    addInline(item.text, font: fonts.serif(12), color: item.isChecked == true ? tertiary : ink, style: paragraph(after: 3, indent: 14), prefix: marker)
                }
                add("", font: fonts.serif(4), style: paragraph(after: 4))
            case .orderedList(let items):
                for (index, item) in items.enumerated() {
                    addInline(item, font: fonts.serif(12), style: paragraph(after: 3, indent: 14), prefix: "\(index + 1).  ")
                }
                add("", font: fonts.serif(4), style: paragraph(after: 4))
            case .quote(let text):
                addInline(text, font: fonts.serif(12, italic: true), color: secondary, style: paragraph(after: 9, indent: 18))
            case .code(_, let text):
                let style = paragraph(after: 9, indent: 10, lineSpacing: 1)
                output.append(NSAttributedString(string: text + "\n", attributes: [
                    .font: fonts.mono(10), .foregroundColor: ink, .backgroundColor: shade, .paragraphStyle: style,
                ]))
            case .table(let table):
                output.append(tableString(table.normalized, fonts: fonts))
                add("", font: fonts.serif(6), style: paragraph(after: 6))
            case .image(let alt, let source):
                if let id = NoteAttachment.id(fromReference: source), let data = note.attachment(id)?.data,
                   let image = NSImage(data: data) {
                    // Sayfa genişliğine sığdır (A4, 2 cm kenar).
                    let maxWidth: CGFloat = 480
                    let scale = min(1, maxWidth / max(image.size.width, 1))
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
                    let line = NSMutableAttributedString(attachment: attachment)
                    line.append(NSAttributedString(string: "\n"))
                    line.addAttribute(.paragraphStyle, value: paragraph(after: 4), range: NSRange(location: 0, length: line.length))
                    output.append(line)
                    if !alt.isEmpty { add(alt, font: fonts.sans(9), color: secondary, style: paragraph(after: 10)) }
                } else {
                    add(String(localized: "[Görsel: \(alt)]"), font: fonts.sans(10), color: secondary, style: paragraph(after: 9))
                }
            case .attachment(let name, _):
                add("📎 " + name, font: fonts.sans(11), color: secondary, style: paragraph(after: 9))
            case .rule:
                add("―――", font: fonts.sans(10), color: rule, style: paragraph(spacingBefore: 4, after: 10))
            }
        }
        return output
    }

    /// Gerçek tablo (NSTextTable): PDF'de çizgili, Word'de düzenlenebilir tablo olarak çıkar.
    private static func tableString(_ table: MarkdownTable, fonts: Fonts) -> NSAttributedString {
        let textTable = NSTextTable()
        textTable.numberOfColumns = table.columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let output = NSMutableAttributedString()
        for (rowIndex, row) in ([table.header] + table.rows).enumerated() {
            for (column, cell) in row.enumerated() {
                let block = NSTextTableBlock(table: textTable, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setBorderColor(rule)
                block.setWidth(0.75, type: .absoluteValueType, for: .border)
                block.setWidth(5, type: .absoluteValueType, for: .padding)
                if rowIndex == 0 { block.backgroundColor = shade }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                let font = rowIndex == 0 ? fonts.sans(10.5, weight: .semibold) : fonts.sans(10.5)
                let cellString = NSMutableAttributedString(attributedString: inline(cell, font: font, color: ink, fonts: fonts, style: style))
                cellString.append(NSAttributedString(string: "\n", attributes: [.font: font]))
                cellString.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cellString.length))
                output.append(cellString)
            }
        }
        return output
    }

    /// Satır içi markdown (kalın, italik, kod, bağlantı) → yazı tipi öznitelikleri.
    private static func inline(_ text: String, font: NSFont, color: NSColor, fonts: Fonts, style: NSParagraphStyle) -> NSAttributedString {
        let parsed = MarkdownBodyView.inline(text)
        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let content = String(parsed[run.range].characters)
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: style]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    runFont = fonts.mono(font.pointSize - 1)
                    attributes[.backgroundColor] = shade
                }
                if intent.contains(.stronglyEmphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
                }
                if intent.contains(.emphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
            }
            attributes[.font] = runFont
            output.append(NSAttributedString(string: content, attributes: attributes))
        }
        return output
    }

    // MARK: - PDF ve Word

    /// A4, 2 cm kenar boşluklu, sayfalara bölünmüş PDF.
    static func pdf(_ text: NSAttributedString) -> Data {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
        printInfo.topMargin = 56.7
        printInfo.bottomMargin = 56.7
        printInfo.leftMargin = 56.7
        printInfo.rightMargin = 56.7
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isVerticallyCentered = false
        printInfo.isHorizontallyCentered = false

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.drawsBackground = false
        textView.textStorage?.setAttributedString(text)
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
            let height = layoutManager.usedRect(for: container).height
            textView.setFrameSize(NSSize(width: width, height: max(height, 100)))
        }

        let data = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(with: textView, inside: textView.bounds, to: data, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
        return data as Data
    }

    static func docx(_ text: NSAttributedString) throws -> Data {
        try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
    }
}
