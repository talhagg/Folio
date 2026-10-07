import Foundation

/// Not listesindeki grup başlıkları. Sabitlenenler her zaman en üsttedir.
enum DateGroup: Int, CaseIterable, Comparable, Sendable {
    case pinned, today, yesterday, thisWeek, thisMonth, older

    static func < (lhs: DateGroup, rhs: DateGroup) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .pinned: String(localized: "Sabitlenenler")
        case .today: String(localized: "Bugün")
        case .yesterday: String(localized: "Dün")
        case .thisWeek: String(localized: "Bu hafta")
        case .thisMonth: String(localized: "Bu ay")
        case .older: String(localized: "Daha eski")
        }
    }

    /// Tarihin düştüğü grup (sabitlenme hariç). Gelecek tarihler bugün sayılır.
    static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> DateGroup {
        if date >= now || calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true { return .thisWeek }
        if calendar.dateInterval(of: .month, for: now)?.contains(date) == true { return .thisMonth }
        return .older
    }
}

struct NoteGroup: Identifiable {
    let group: DateGroup
    let notes: [Note]
    var id: DateGroup { group }
}

enum DateGrouping {
    /// Notları `updatedAt`'e göre gruplar; gruplar ve içleri yeniden eskiye sıralıdır.
    static func groups(for notes: [Note], now: Date, calendar: Calendar = .current) -> [NoteGroup] {
        let buckets = Dictionary(grouping: notes) { note in
            note.isPinned ? DateGroup.pinned : DateGroup.of(note.updatedAt, now: now, calendar: calendar)
        }
        return buckets.keys.sorted().map { group in
            NoteGroup(group: group, notes: buckets[group, default: []].sorted { $0.updatedAt > $1.updatedAt })
        }
    }

    /// Satırdaki kısa tarih: bugün → saat, dün → "Dün", bu hafta → gün adı, daha eski → "5 Eki".
    static func rowDateText(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        if let locale = calendar.locale { style.locale = locale }
        switch DateGroup.of(date, now: now, calendar: calendar) {
        case .today:
            return date.formatted(style.hour().minute())
        case .yesterday:
            return String(localized: "Dün")
        case .thisWeek:
            return date.formatted(style.weekday(.abbreviated))
        case .thisMonth, .older, .pinned:
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                return date.formatted(style.day().month(.abbreviated))
            }
            return date.formatted(style.day().month(.abbreviated).year())
        }
    }
}

extension DateGrouping {
    /// Editör üst satırı: "bugün 14:32", "dün 09:10", "5 Eki", başka yıl "5 Eki 2025".
    static func editorDateText(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        if let locale = calendar.locale { style.locale = locale }
        let time = date.formatted(style.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "bugün \(time)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "dün \(time)")
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style.day().month(.abbreviated))
        }
        return date.formatted(style.day().month(.abbreviated).year())
    }
}

enum MarkdownPreview {
    /// Liste önizlemesi için markdown işaretlerini atar, satırları birleştirir.
    static func plainText(_ markdown: String, limit: Int = 200) -> String {
        let lines = markdown
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacing(/^(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|>\s*|\d+\.\s+)/, with: "")
            }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: " ")
            .replacing(/[`*_]/, with: "")
        return String(joined.prefix(limit))
    }
}
