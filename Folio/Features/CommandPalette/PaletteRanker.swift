import Foundation

/// Komut paletinde bir satır: not, defter, bölüm, etiket ya da komut.
struct PaletteItem: Identifiable {
    enum Kind: Int, Sendable {
        case command, note, notebook, section, tag
    }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String = ""
    var symbolName: String
    /// Başlıkta görünmeyen ama aramada eşleşen sözcükler (ör. "tema" → "Koyu").
    var keywords: String = ""
    var shortcut: String?
    let perform: @MainActor () -> Void
}

/// Paletin sıralaması: tam eşleşme > baştan > sözcük başı > içerir > harf sırası (bulanık).
/// Büyük/küçük harf ve aksan (ç, ğ, ı, ö, ş, ü) gözetmez.
enum PaletteRanker {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// `nil` → eşleşmiyor. Büyük puan daha iyi.
    static func score(query: String, in text: String) -> Int? {
        let q = normalized(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return 0 }
        let t = normalized(text)
        guard !t.isEmpty else { return nil }
        let lengthPenalty = min(t.count, 100) / 4
        if t == q { return 1000 }
        // Tam sözcük ("not" → "Not Listesi") sözcüğün parçasından ("Notlarda") önde.
        func endsWord(_ end: String.Index) -> Bool { end == t.endIndex || !t[end].isLetter }
        if t.hasPrefix(q) { return 800 - lengthPenalty + (endsWord(t.index(t.startIndex, offsetBy: q.count)) ? 50 : 0) }
        if let range = t.range(of: q) {
            let atWordStart = range.lowerBound == t.startIndex || !t[t.index(before: range.lowerBound)].isLetter
            return (atWordStart ? 600 : 400) - lengthPenalty + (atWordStart && endsWord(range.upperBound) ? 50 : 0)
        }
        // Bulanık: sorgunun harfleri sırayla geçiyor mu; boşluklar puan düşürür.
        var gaps = 0
        var index = t.startIndex
        for character in q where character != " " {
            guard let found = t[index...].firstIndex(of: character) else { return nil }
            gaps += t.distance(from: index, to: found)
            index = t.index(after: found)
        }
        return max(1, 200 - gaps * 4 - lengthPenalty)
    }

    /// Başlık ve anahtar sözcüklere göre puanlar; eşit puanda verilen sıra korunur.
    static func rank(_ items: [PaletteItem], query: String, limit: Int = 50) -> [PaletteItem] {
        let scored = items.enumerated().compactMap { offset, item -> (Int, Int, PaletteItem)? in
            let titleScore = score(query: query, in: item.title)
            let keywordScore = item.keywords.isEmpty ? nil : score(query: query, in: item.keywords).map { $0 - 150 }
            let subtitleScore = item.subtitle.isEmpty ? nil : score(query: query, in: item.subtitle).map { $0 - 300 }
            guard let best = [titleScore, keywordScore, subtitleScore].compactMap({ $0 }).max() else { return nil }
            return (best, offset, item)
        }
        return scored
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .prefix(limit)
            .map(\.2)
    }
}
