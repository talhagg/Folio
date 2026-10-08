import Foundation

/// Yazarken oluşan geçici biçim hatalarını düzeltir.
///
/// Kalın yazarken boşluk konunca metin `**kalın **` olur; markdown'da kapanıştan önce boşluk
/// olamadığı için önizleme ve dışa aktarmada yıldızlar görünürdü. Boşluk biçimin dışına taşınır
/// (`**kalın** `) ve içi boş `****` çiftleri silinir. Kod blokları ve satır içi kod korunur;
/// iki yanı da boşluklu `*` (ör. `5 * 3 * 2`) aritmetik sayılıp dokunulmaz.
enum MarkdownNormalizer {
    private static let emptyBold = try! NSRegularExpression(pattern: #"(?<!\*)\*\*\*\*(?!\*)"#)
    private static let bold = try! NSRegularExpression(pattern: #"\*\*([^*\n]+?)\*\*"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![*\w])\*([^*\n]+?)\*(?![*\w])"#)
    private static let inlineCode = try! NSRegularExpression(pattern: "`[^`\n]*`")

    static func emphasisSpacing(_ text: String) -> String {
        var inFence = false
        return text.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                return line
            }
            return inFence ? line : normalizeLine(line)
        }.joined(separator: "\n")
    }

    /// Satır içi kod parçaları dışındaki bölümleri düzeltir.
    private static func normalizeLine(_ line: String) -> String {
        let ns = line as NSString
        var result = ""
        var cursor = 0
        for match in inlineCode.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            result += normalizeSegment(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += ns.substring(with: match.range)
            cursor = match.range.upperBound
        }
        result += normalizeSegment(ns.substring(from: cursor))
        return result
    }

    private static func normalizeSegment(_ segment: String) -> String {
        var text = replace(emptyBold, in: segment) { _ in "" }
        text = replace(bold, in: text) { content in moveSpaces(content, marker: "**") }
        text = replace(italic, in: text) { content in moveSpaces(content, marker: "*") }
        return text
    }

    /// İçerik bir yanında boşluk taşıyorsa boşluğu dışarı alır; iki yanı da boşluksa dokunmaz.
    private static func moveSpaces(_ content: String, marker: String) -> String? {
        let core = content.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return nil }
        let leading = String(content.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(content.reversed().prefix { $0 == " " || $0 == "\t" })
        guard leading.isEmpty != trailing.isEmpty else { return nil }
        return leading + marker + core + marker + trailing
    }

    /// `transform` içeriği alır; `nil` dönerse eşleşme olduğu gibi kalır.
    private static func replace(_ regex: NSRegularExpression, in text: String, _ transform: (String) -> String?) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let content = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                ? ns.substring(with: match.range(at: 1)) : ""
            result += transform(content) ?? ns.substring(with: match.range)
            cursor = match.range.upperBound
        }
        return result + ns.substring(from: cursor)
    }
}
