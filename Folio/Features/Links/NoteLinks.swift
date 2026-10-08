import Foundation
import Observation

/// Uygulama içi bağlantılar: `folio://note/<id>`, `folio://title/<başlık>`, `folio://tag/<etiket>`.
/// Not bağlantıları, etiketler, hatırlatıcı bildirimleri ve Spotlight aynı yolu kullanır.
enum AppLink: Hashable, Sendable {
    case note(UUID)
    case noteTitle(String)
    case tag(String)

    static let scheme = "folio"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .note(let id):
            components.host = "note"
            components.path = "/" + id.uuidString
        case .noteTitle(let title):
            components.host = "title"
            components.path = "/" + title
        case .tag(let tag):
            components.host = "tag"
            components.path = "/" + tag
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return nil }
        let value = String(components.path.drop { $0 == "/" })
        guard !value.isEmpty else { return nil }
        switch host {
        case "note":
            guard let id = UUID(uuidString: value) else { return nil }
            self = .note(id)
        case "title": self = .noteTitle(value)
        case "tag": self = .tag(value)
        default: return nil
        }
    }
}

/// Bağlantı istekleri için ortak kuyruk; ana pencere dinler (bildirim, Spotlight, yapışkan not, menü çubuğu).
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()
    var request: AppLink?

    func open(_ link: AppLink) { request = link }
}

/// `#etiket` ve `[[Not adı]]` sözdizimi. Kod blokları ve satır içi kod yok sayılır.
enum NoteLinkSyntax {
    /// Harfle başlar; harf, rakam, `_`, `-`, `/` içerebilir. `# Başlık` (boşluklu) etiket değildir.
    private static let tagPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_#/&\]\)])#(\p{L}[\p{L}\p{N}_\-/]{0,39})"#)
    private static let wikiPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]{1,120})\]\]"#)
    private static let inlineCode = try! NSRegularExpression(pattern: "`[^`\n]*`")

    static func normalizedTag(_ tag: String) -> String {
        tag.lowercased(with: Locale(identifier: "tr_TR"))
    }

    /// Metindeki etiketler (küçük harf, tekrarsız, ilk görülme sırasıyla).
    static func tags(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        forEachProseRange(in: text) { line, range in
            for match in tagPattern.matches(in: line, range: range) {
                let tag = normalizedTag((line as NSString).substring(with: match.range(at: 1)))
                if seen.insert(tag).inserted { result.append(tag) }
            }
        }
        return result
    }

    /// `[[…]]` ile bağlanan not başlıkları.
    static func linkedTitles(in text: String) -> [String] {
        var result: [String] = []
        forEachProseRange(in: text) { line, range in
            for match in wikiPattern.matches(in: line, range: range) {
                let title = (line as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { result.append(title) }
            }
        }
        return result
    }

    /// Önizleme için: `[[X]]` → `[X](folio://title/X)`, `#etiket` → `[#etiket](folio://tag/etiket)`.
    static func displayMarkdown(_ text: String) -> String {
        rewriteProse(text) { segment in
            var result = replace(wikiPattern, in: segment) { match, ns in
                let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                return "[\(escapeLinkText(title))](\(AppLink.noteTitle(title).url.absoluteString))"
            }
            result = replace(tagPattern, in: result) { match, ns in
                let tag = ns.substring(with: match.range(at: 1))
                return "[#\(tag)](\(AppLink.tag(normalizedTag(tag)).url.absoluteString))"
            }
            return result
        }
    }

    /// Dışa aktarma için: `[[X]]` → `X`.
    static func plain(_ text: String) -> String {
        rewriteProse(text) { segment in
            replace(wikiPattern, in: segment) { match, ns in
                ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    /// `title` başlıklı nota `[[…]]` ile bağlanan notlar (büyük/küçük harf duyarsız, kendisi hariç).
    static func backlinks(to title: String, in notes: [Note], excluding id: UUID) -> [Note] {
        let key = normalizedTag(title.trimmingCharacters(in: .whitespaces))
        guard !key.isEmpty else { return [] }
        return notes.filter { note in
            note.id != id && !note.isTrashed
                && linkedTitles(in: note.body).contains { normalizedTag($0) == key }
        }
    }

    // MARK: - Yardımcılar

    private static func escapeLinkText(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    /// Kod blokları dışındaki her satırda, satır içi kod dışındaki aralıkları dolaşır.
    private static func forEachProseRange(in text: String, _ body: (String, NSRange) -> Void) {
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence else { continue }
            let ns = line as NSString
            var cursor = 0
            for code in inlineCode.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                body(line, NSRange(location: cursor, length: code.range.location - cursor))
                cursor = code.range.upperBound
            }
            body(line, NSRange(location: cursor, length: ns.length - cursor))
        }
    }

    private static func rewriteProse(_ text: String, _ transform: (String) -> String) -> String {
        var inFence = false
        return text.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); return line }
            guard !inFence else { return line }
            let ns = line as NSString
            var result = ""
            var cursor = 0
            for code in inlineCode.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                result += transform(ns.substring(with: NSRange(location: cursor, length: code.range.location - cursor)))
                result += ns.substring(with: code.range)
                cursor = code.range.upperBound
            }
            return result + transform(ns.substring(from: cursor))
        }.joined(separator: "\n")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, _ transform: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(match, ns)
            cursor = match.range.upperBound
        }
        return result + ns.substring(from: cursor)
    }
}

extension Note {
    /// Başlık ve gövdedeki etiketler.
    var tags: [String] { NoteLinkSyntax.tags(in: title + "\n" + body) }
}
