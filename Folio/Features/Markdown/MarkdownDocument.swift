import Foundation

/// Not gövdesinin blok düzeyinde markdown ayrıştırması. Satır içi biçim (kalın, kod, bağlantı)
/// görünümde `AttributedString(markdown:)` ile çözülür.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([ListItem])
    case orderedList([String])
    case quote(String)
    case code(language: String?, text: String)
    case table(MarkdownTable)
    case rule
    /// Tek başına satırdaki `![ad](kaynak)`.
    case image(alt: String, source: String)
    /// Tek başına satırdaki `[ad](attachment:<id>)`.
    case attachment(name: String, source: String)

    struct ListItem: Equatable, Sendable {
        var text: String
        /// `- [ ]` / `- [x]` satırları için.
        var isChecked: Bool?
    }
}

/// Bloğun gövdedeki satır aralığıyla birlikte hali; tablo düzenlerken yerine yazmak için.
struct ParsedBlock: Equatable, Sendable {
    var block: MarkdownBlock
    var lines: Range<Int>
}

struct MarkdownTable: Equatable, Sendable {
    var header: [String]
    var rows: [[String]]

    var columnCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    /// Eksik hücreleri boşlukla tamamlar.
    var normalized: MarkdownTable {
        let count = max(columnCount, 1)
        func pad(_ row: [String]) -> [String] { row + Array(repeating: "", count: max(0, count - row.count)) }
        return MarkdownTable(header: pad(header), rows: rows.map(pad))
    }

    static func empty(columns: Int, rows: Int) -> MarkdownTable {
        MarkdownTable(
            header: (1...max(columns, 1)).map { String(localized: "Sütun \($0)") },
            rows: Array(repeating: Array(repeating: "", count: max(columns, 1)), count: max(rows, 1))
        )
    }

    /// GitHub biçiminde markdown; sütunlar hizalanır.
    var markdown: String {
        let table = normalized
        let all = [table.header] + table.rows
        let widths = (0..<table.columnCount).map { column in
            max(3, all.map { Self.escape($0[column]).count }.max() ?? 3)
        }
        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { index, cell in
                let text = Self.escape(cell)
                return text + String(repeating: " ", count: widths[index] - text.count)
            }.joined(separator: " | ") + " |"
        }
        let separator = "| " + widths.map { String(repeating: "-", count: $0) }.joined(separator: " | ") + " |"
        return ([line(table.header), separator] + table.rows.map(line)).joined(separator: "\n")
    }

    static func escape(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

enum MarkdownDocument {
    static func parse(_ text: String) -> [ParsedBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [ParsedBlock] = []
        var index = 0

        func trimmed(_ i: Int) -> String { lines[i].trimmingCharacters(in: .whitespaces) }

        while index < lines.count {
            let line = trimmed(index)
            let start = index

            if line.isEmpty {
                index += 1
                continue
            }

            // Kod bloğu
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count, !trimmed(index).hasPrefix("```") {
                    body.append(lines[index])
                    index += 1
                }
                index = min(index + 1, lines.count)
                blocks.append(.init(block: .code(language: language.isEmpty ? nil : language, text: body.joined(separator: "\n")), lines: start..<index))
                continue
            }

            // Tablo: başlık satırı + ayırıcı
            if line.contains("|"), index + 1 < lines.count, isTableSeparator(trimmed(index + 1)) {
                let header = cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, trimmed(index).contains("|"), !trimmed(index).isEmpty {
                    rows.append(cells(trimmed(index)))
                    index += 1
                }
                blocks.append(.init(block: .table(MarkdownTable(header: header, rows: rows)), lines: start..<index))
                continue
            }

            // Görsel ya da ek (satırda tek başına)
            if let match = line.wholeMatch(of: /!\[([^\]]*)\]\(([^)\s]+)\)/) {
                blocks.append(.init(block: .image(alt: String(match.1), source: String(match.2)), lines: start..<index + 1))
                index += 1
                continue
            }
            if let match = line.wholeMatch(of: /\[([^\]]+)\]\((attachment:[0-9A-Fa-f-]{36})\)/) {
                blocks.append(.init(block: .attachment(name: String(match.1), source: String(match.2)), lines: start..<index + 1))
                index += 1
                continue
            }

            // Başlık
            if let heading = heading(line) {
                blocks.append(.init(block: .heading(level: heading.level, text: heading.text), lines: start..<index + 1))
                index += 1
                continue
            }

            // Yatay çizgi
            if line.count >= 3, Set(line.replacingOccurrences(of: " ", with: "")).count == 1,
               ["-", "*", "_"].contains(line.first) {
                blocks.append(.init(block: .rule, lines: start..<index + 1))
                index += 1
                continue
            }

            // Alıntı
            if line.hasPrefix(">") {
                var quote: [String] = []
                while index < lines.count, trimmed(index).hasPrefix(">") {
                    quote.append(String(trimmed(index).dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.init(block: .quote(quote.joined(separator: "\n")), lines: start..<index))
                continue
            }

            // Madde işaretli liste (görev kutuları dahil)
            if bulletItem(line) != nil {
                var items: [MarkdownBlock.ListItem] = []
                while index < lines.count, let item = bulletItem(trimmed(index)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.init(block: .bulletList(items), lines: start..<index))
                continue
            }

            // Numaralı liste
            if orderedItem(line) != nil {
                var items: [String] = []
                while index < lines.count, let item = orderedItem(trimmed(index)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.init(block: .orderedList(items), lines: start..<index))
                continue
            }

            // Paragraf: bir sonraki boş satıra ya da blok başlangıcına kadar.
            var paragraph: [String] = []
            while index < lines.count {
                let current = trimmed(index)
                if current.isEmpty || (index > start && startsBlock(current, next: index + 1 < lines.count ? trimmed(index + 1) : nil)) {
                    break
                }
                paragraph.append(current)
                index += 1
            }
            blocks.append(.init(block: .paragraph(paragraph.joined(separator: "\n")), lines: start..<index))
        }
        return blocks
    }

    /// Metinde geçen ek kimlikleri.
    static func attachmentIDs(in text: String) -> [UUID] {
        text.matches(of: /attachment:([0-9A-Fa-f-]{36})/).compactMap { UUID(uuidString: String($0.1)) }
    }

    /// Gövdede `lines` aralığını `replacement` ile değiştirir.
    static func replacingLines(_ range: Range<Int>, in text: String, with replacement: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let lower = min(range.lowerBound, lines.count)
        let upper = min(range.upperBound, lines.count)
        lines.replaceSubrange(lower..<upper, with: replacement.components(separatedBy: "\n"))
        return lines.joined(separator: "\n")
    }

    /// Gövdenin sonuna boş satırla ayrılmış bir blok ekler.
    static func appendingBlock(_ block: String, to text: String) -> String {
        let base = text.trimmingCharacters(in: .newlines)
        return base.isEmpty ? block + "\n" : base + "\n\n" + block + "\n"
    }

    // MARK: - Yardımcılar

    static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        return line.wholeMatch(of: /\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/) != nil
    }

    static func cells(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") && !content.hasSuffix("\\|") { content.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in content {
            if escaped {
                current.append(character == "|" ? "|" : "\\" + String(character))
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        guard let match = line.wholeMatch(of: /(#{1,6})\s+(.*)/) else { return nil }
        return (match.1.count, String(match.2).trimmingCharacters(in: .whitespaces))
    }

    private static func bulletItem(_ line: String) -> MarkdownBlock.ListItem? {
        // "- " yazıp henüz içerik girilmemiş satır da (kırpılınca "-") boş madde sayılır.
        guard let match = line.wholeMatch(of: /[-*+](?:\s+(.*))?/) else { return nil }
        let text = match.1.map(String.init) ?? ""
        if let task = text.wholeMatch(of: /\[( |x|X)\]\s*(.*)/) {
            return .init(text: String(task.2), isChecked: task.1 != " ")
        }
        return .init(text: text, isChecked: nil)
    }

    private static func orderedItem(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /\d+[.)](?:\s+(.*))?/) else { return nil }
        return match.1.map(String.init) ?? ""
    }

    private static func startsBlock(_ line: String, next: String?) -> Bool {
        if line.hasPrefix("```") || line.hasPrefix(">") || heading(line) != nil { return true }
        if line.wholeMatch(of: /!?\[[^\]]*\]\([^)\s]+\)/) != nil, line.hasPrefix("!") || line.contains("](attachment:") { return true }
        if bulletItem(line) != nil || orderedItem(line) != nil { return true }
        if line.contains("|"), let next, isTableSeparator(next) { return true }
        return false
    }
}
