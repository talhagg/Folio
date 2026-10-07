import Foundation

/// Kenar çubuğundaki akıllı filtreler.
enum SmartFilter: String, CaseIterable, Hashable, Sendable {
    case all, today, inProgress, pinned

    var title: String {
        switch self {
        case .all: String(localized: "Tüm Notlar")
        case .today: String(localized: "Bugün")
        case .inProgress: String(localized: "Devam Edenler")
        case .pinned: String(localized: "Sabitlenenler")
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray"
        case .today: "sun.max"
        case .inProgress: "circle.lefthalf.filled"
        case .pinned: "pin"
        }
    }

    /// `today`: bugün düzenlenen ya da hedef tarihi bugün olan notlar. Çöpteki notlar hiçbirine girmez.
    func includes(_ note: Note, now: Date, calendar: Calendar = .current) -> Bool {
        guard !note.isTrashed else { return false }
        return switch self {
        case .all:
            true
        case .today:
            calendar.isDate(note.updatedAt, inSameDayAs: now)
                || note.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        case .inProgress:
            note.status == .doing
        case .pinned:
            note.isPinned
        }
    }
}

/// Defter/bölüm modelin kalıcı `id`'siyle tutulur; `persistentModelID` kaydedilmemiş nesnelerde geçicidir
/// ve kayıttan sonra geçersizleşir.
enum SidebarSelection: Hashable, Sendable {
    case smart(SmartFilter)
    case notebook(UUID)
    case section(UUID)
    /// Son Silinenler.
    case trash

    func includes(_ note: Note, now: Date, calendar: Calendar = .current) -> Bool {
        if self == .trash { return note.isTrashed }
        guard !note.isTrashed else { return false }
        switch self {
        case .trash:
            return true
        case .smart(let filter):
            return filter.includes(note, now: now, calendar: calendar)
        case .notebook(let id):
            return note.section?.notebook?.id == id
        case .section(let id):
            return note.section?.id == id
        }
    }
}
