import SwiftUI

/// Arama eşleşmelerini bulur ve vurgular. Büyük/küçük harf ve aksan duyarsızdır; ayrıca Türkçe
/// i/ı/I/İ birbirine eşittir — böylece "api" "API"yi, "akisi" "akışı"nı bulur (Türkçe locale'deki
/// `localizedStandardContains` bunları ayırır).
enum SearchHighlighter {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func contains(_ text: String, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return fold(text).range(of: fold(query), options: options) != nil
    }

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        // `fold` karakterleri bire bir değiştirir; karakter ofsetleri iki metinde aynıdır.
        let folded = fold(text)
        let needle = fold(query)
        let originalIndices = Array(text.indices) + [text.endIndex]
        var result: [Range<String.Index>] = []
        var searchRange = folded.startIndex..<folded.endIndex
        while let found = folded.range(of: needle, options: options, range: searchRange), !found.isEmpty {
            let lower = folded.distance(from: folded.startIndex, to: found.lowerBound)
            let upper = folded.distance(from: folded.startIndex, to: found.upperBound)
            result.append(originalIndices[lower]..<originalIndices[upper])
            searchRange = found.upperBound..<folded.endIndex
        }
        return result
    }

    private static func fold(_ string: String) -> String {
        String(string.map { character -> Character in
            switch character {
            case "ı": "i"
            case "İ": "I"
            default: character
            }
        })
    }

    /// Eşleşmeleri `highlight` zeminiyle işaretlenmiş metin.
    static func attributed(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges(of: query, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].backgroundColor = Color.ds.highlight
            attributed[lower..<upper].foregroundColor = Color.ds.ink
        }
        return attributed
    }
}

enum SearchSnippet {
    /// Satır önizlemesi. Arama yoksa gövdenin başı; eşleşme gövdenin derinindeyse çevresi;
    /// yalnızca görevde eşleşiyorsa o görevin metni.
    static func preview(body: String, taskTexts: [String], query: String, context: Int = 32) -> String {
        let plain = MarkdownPreview.plainText(body, limit: 2_000)
        guard !query.isEmpty else { return String(plain.prefix(200)) }

        if let match = SearchHighlighter.ranges(of: query, in: plain).first {
            let offset = plain.distance(from: plain.startIndex, to: match.lowerBound)
            guard offset > context else { return String(plain.prefix(200)) }
            var start = plain.index(match.lowerBound, offsetBy: -context)
            // Kelimenin ortasından başlamasın.
            if let space = plain[start..<match.lowerBound].firstIndex(of: " ") {
                start = plain.index(after: space)
            }
            return "…" + String(plain[start...].prefix(200))
        }

        if let task = taskTexts.first(where: { SearchHighlighter.contains($0, query) }) {
            return "☐ " + task
        }
        return String(plain.prefix(200))
    }
}
