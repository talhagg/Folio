import SwiftUI

enum NoteStatus: String, CaseIterable, Codable, Sendable {
    case todo, doing, done, blocked

    /// Bloke override'ı ve ilerlemeden durumu çıkarır. Görevi olmayan notta durum elle (panodan)
    /// belirlenir ve `overrideRaw`'da saklanır; yoksa başlanmadı sayılır.
    static func resolve(progress: Double?, overrideRaw: String?) -> NoteStatus {
        if overrideRaw == NoteStatus.blocked.rawValue { return .blocked }
        guard let progress else { return overrideRaw.flatMap(NoteStatus.init(rawValue:)) ?? .todo }
        if progress <= 0 { return .todo }
        if progress >= 1 { return .done }
        return .doing
    }

    var title: String {
        switch self {
        case .todo: String(localized: "Başlanmadı")
        case .doing: String(localized: "Devam ediyor")
        case .done: String(localized: "Tamamlandı")
        case .blocked: String(localized: "Bloke")
        }
    }

    var symbolName: String {
        switch self {
        case .todo: "circle"
        case .doing: "circle.lefthalf.filled"
        case .done: "checkmark.circle"
        case .blocked: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .todo: Color.ds.statusTodo
        case .doing: Color.ds.statusDoing
        case .done: Color.ds.statusDone
        case .blocked: Color.ds.statusBlocked
        }
    }
}
