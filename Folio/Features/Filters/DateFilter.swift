import Foundation

/// Liste üstündeki tarih filtresi. Notun `updatedAt` tarihine uygulanır.
enum DateFilter: Hashable, Sendable {
    case all, today, week, month
    case custom(start: Date, end: Date)

    /// Segmentli kontroldeki parça.
    enum Kind: String, CaseIterable, Hashable, Sendable {
        case all, today, week, month, custom

        var title: String {
            switch self {
            case .all: String(localized: "Tümü")
            case .today: String(localized: "Bugün")
            case .week: String(localized: "Bu Hafta")
            case .month: String(localized: "Bu Ay")
            case .custom: String(localized: "Özel")
            }
        }
    }

    var kind: Kind {
        switch self {
        case .all: .all
        case .today: .today
        case .week: .week
        case .month: .month
        case .custom: .custom
        }
    }

    /// `nil` → sınırsız. Hafta başlangıcı `calendar`'ın locale'inden gelir.
    func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        case .custom(let start, let end):
            let lower = calendar.startOfDay(for: min(start, end))
            let upperDay = calendar.startOfDay(for: max(start, end))
            let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
            return DateInterval(start: lower, end: upper)
        }
    }

    /// Özet satırı ve çip için ("Bu hafta", "7–14 Eki").
    var summaryTitle: String {
        switch self {
        case .all: String(localized: "Tüm tarihler")
        case .today: String(localized: "Bugün")
        case .week: String(localized: "Bu hafta")
        case .month: String(localized: "Bu ay")
        case .custom(let start, let end):
            (min(start, end)..<max(start, end)).formatted(.interval.day().month(.abbreviated))
        }
    }
}
