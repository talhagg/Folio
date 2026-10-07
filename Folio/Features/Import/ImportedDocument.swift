import Foundation

/// İçe aktarılan tek bir not.
struct ImportedDocument: Equatable, Sendable {
    var title: String
    var markdown: String
    var createdAt: Date?
    var tasks: [ImportedTask] = []
    var isPinned = false
    var dueDate: Date?
}

struct ImportedTask: Equatable, Sendable {
    var text: String
    var isDone: Bool
    var dueDate: Date?
}

enum ImportError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case unreadable(String)
    case empty
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            if ["xls", "doc"].contains(ext) {
                return String(localized: "Eski .\(ext) biçimi desteklenmiyor; dosyayı .\(ext)x olarak kaydedip tekrar deneyin.")
            }
            return String(localized: ".\(ext) dosyaları içe aktarılamıyor. Desteklenenler: CSV, JSON, Excel (.xlsx), Word (.docx), Markdown, TXT, HTML.")
        case .unreadable(let reason):
            return String(localized: "Dosya okunamadı: \(reason)")
        case .empty:
            return String(localized: "İçe aktarılacak içerik bulunamadı.")
        case .tooLarge:
            return String(localized: "Dosya çok büyük (en fazla 50 MB).")
        }
    }
}

/// Tablo biçimli verinin (CSV, Excel, JSON dizisi) nota dönüşümü.
///
/// Başlık sütunu ("title", "başlık", "konu"…) varsa her satır ayrı bir not olur; gövde sütunu
/// ("body", "içerik", "açıklama"…) notun metni, diğer sütunlar madde listesi olur. Yoksa tüm veri
/// tek bir nota markdown tablosu olarak konur.
enum TabularImport {
    static let maxNotes = 2_000

    private static let titleKeys: Set<String> = ["title", "baslik", "name", "ad", "isim", "subject", "konu", "summary", "ozet", "baslik adi"]
    private static let bodyKeys: Set<String> = ["body", "content", "icerik", "text", "metin", "description", "aciklama", "notes", "not", "note", "notlar"]
    private static let dateKeys: Set<String> = ["date", "tarih", "created", "createdat", "created_at", "created at", "olusturulma", "olusturma tarihi"]

    static func documents(header: [String], rows: [[String]], fallbackTitle: String) -> [ImportedDocument] {
        let rows = rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !header.isEmpty || !rows.isEmpty else { return [] }
        let keys = header.map(normalizedKey)

        guard let titleIndex = keys.firstIndex(where: titleKeys.contains) else {
            return [ImportedDocument(title: fallbackTitle, markdown: MarkdownTable(header: header, rows: rows).markdown)]
        }
        let bodyIndex = keys.firstIndex(where: bodyKeys.contains)
        let dateIndex = keys.firstIndex(where: dateKeys.contains)

        return rows.prefix(maxNotes).map { row in
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var parts: [String] = []
            let body = cell(bodyIndex)
            if !body.isEmpty { parts.append(body) }
            let extras = header.indices
                .filter { $0 != titleIndex && $0 != bodyIndex && $0 != dateIndex }
                .compactMap { index -> String? in
                    let value = cell(index)
                    return value.isEmpty ? nil : "- **\(header[index]):** \(value)"
                }
            if !extras.isEmpty { parts.append(extras.joined(separator: "\n")) }
            let title = cell(titleIndex)
            return ImportedDocument(
                title: title.isEmpty ? String(localized: "Başlıksız not") : title,
                markdown: parts.joined(separator: "\n\n"),
                createdAt: DateParsing.parse(cell(dateIndex))
            )
        }
    }

    static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "I")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum DateParsing {
    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd.MM.yyyy HH:mm", "dd.MM.yyyy", "dd/MM/yyyy", "d.M.yyyy",
    ]

    static func parse(_ text: String) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

enum TextDecoding {
    /// UTF-8 (BOM'lu/BOM'suz), UTF-16 ve Türkçe Windows kod sayfası denenir.
    static func string(from data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if let text = String(data: data, encoding: .utf8) { return text }
        let turkish = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: turkish)) ?? String(data: data, encoding: .isoLatin1)
    }
}
