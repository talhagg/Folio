import Foundation

/// JSON → not. Nesne dizisi tablo gibi işlenir (başlık sütunu varsa satır başına not);
/// `notes`/`items`/`data`/`results` altındaki dizi aranır; tek nesne tek not olur; geri kalanı kod bloğu.
enum JSONImporter {
    private static let containerKeys = ["notes", "items", "data", "results", "records", "pages", "notlar"]

    static func documents(from data: Data, fallbackTitle: String) throws -> [ImportedDocument] {
        // Folio'nun kendi yedeği: görevler, sabitleme ve hedef tarihleriyle geri yüklenir.
        if let export = try? FolioExport.decoder.decode(FolioExport.self, from: data), export.app == FolioExport.appName {
            return export.notes.map { note in
                ImportedDocument(
                    title: note.title,
                    markdown: note.body,
                    createdAt: note.createdAt,
                    tasks: note.tasks.map { ImportedTask(text: $0.text, isDone: $0.isDone, dueDate: $0.dueDate) },
                    isPinned: note.isPinned,
                    dueDate: note.dueDate
                )
            }
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ImportError.unreadable(String(localized: "geçerli bir JSON değil"))
        }
        return documents(from: object, fallbackTitle: fallbackTitle)
    }

    static func documents(from object: Any, fallbackTitle: String) -> [ImportedDocument] {
        if let array = object as? [[String: Any]] {
            var header: [String] = []
            for item in array {
                for key in item.keys.sorted() where !header.contains(key) { header.append(key) }
            }
            // Anahtarları anlamlı sıraya koy: başlık önce.
            header.sort { lhs, rhs in rank(lhs) < rank(rhs) }
            let rows = array.map { item in header.map { stringify(item[$0]) } }
            return TabularImport.documents(header: header, rows: rows, fallbackTitle: fallbackTitle)
        }
        if let dictionary = object as? [String: Any] {
            for key in containerKeys {
                if let nested = dictionary.first(where: { TabularImport.normalizedKey($0.key) == key })?.value,
                   nested is [Any] {
                    return documents(from: nested, fallbackTitle: fallbackTitle)
                }
            }
            let keys = dictionary.keys.sorted { rank($0) < rank($1) }
            let documents = TabularImport.documents(header: keys, rows: [keys.map { stringify(dictionary[$0]) }], fallbackTitle: fallbackTitle)
            if documents.count == 1, documents[0].title != fallbackTitle { return documents }
            return [codeDocument(object, title: fallbackTitle)]
        }
        if let array = object as? [Any], !array.isEmpty, array.allSatisfy({ !($0 is [Any]) && !($0 is [String: Any]) }) {
            return [ImportedDocument(title: fallbackTitle, markdown: array.map { "- \(stringify($0))" }.joined(separator: "\n"))]
        }
        return [codeDocument(object, title: fallbackTitle)]
    }

    private static func rank(_ key: String) -> Int {
        let normalized = TabularImport.normalizedKey(key)
        if ["title", "baslik", "name", "ad", "subject", "konu"].contains(normalized) { return 0 }
        if ["body", "content", "icerik", "text", "description", "aciklama"].contains(normalized) { return 1 }
        return 2
    }

    static func stringify(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return ""
        case let string as String: return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        default:
            guard let value, JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else {
                return String(describing: value ?? "")
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static func codeDocument(_ object: Any, title: String) -> ImportedDocument {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
        return ImportedDocument(title: title, markdown: "```json\n\(String(decoding: data, as: UTF8.self))\n```")
    }
}
