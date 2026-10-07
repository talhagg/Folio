import Foundation

enum TestClock {
    /// 2026-10-07 Çarşamba 12:00 UTC
    static let now = Date(timeIntervalSince1970: 1_791_374_400)

    /// Pazartesi başlangıçlı, UTC, Türkçe takvim.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.firstWeekday = 2
        return calendar
    }

    /// `now` gününden `days` gün önce, verilen saat (UTC).
    static func date(daysAgo days: Int, hour: Int = 10, minute: Int = 0) -> Date {
        let calendar = calendar
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }
}
