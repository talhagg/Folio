import Foundation

/// RFC 4180 CSV: tırnaklı alanlar, alan içi satır sonu, "" kaçışı. Ayırıcı (, ; sekme) ilk satırdan seçilir.
enum CSVParser {
    static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let separator = delimiter ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" }
        let candidates: [Character] = [",", ";", "\t"]
        var counts: [Character: Int] = [:]
        var inQuotes = false
        for character in firstLine {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes, candidates.contains(character) { counts[character, default: 0] += 1 }
        }
        return candidates.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? ","
    }

    static func documents(from text: String, fallbackTitle: String) -> [ImportedDocument] {
        let rows = parse(text)
        guard let header = rows.first else { return [] }
        return TabularImport.documents(header: header, rows: Array(rows.dropFirst()), fallbackTitle: fallbackTitle)
    }
}
