import Foundation

/// Not sütununun görünümü: liste, pano (durum sütunları) ya da takvim.
enum ViewMode: String, CaseIterable, Identifiable, Sendable {
    case list, board, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: String(localized: "Liste")
        case .board: String(localized: "Pano")
        case .calendar: String(localized: "Takvim")
        }
    }

    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .board: "rectangle.split.3x1"
        case .calendar: "calendar"
        }
    }
}
