import Foundation

/// Not listesi yoğunluğu: Sade (başlık + tarih) ya da Ayrıntılı (özet, defter, ilerleme).
enum ListDensity: String, CaseIterable, Identifiable, Sendable {
    case compact, detailed

    static let storageKey = "noteList.density"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: String(localized: "Sade")
        case .detailed: String(localized: "Ayrıntılı")
        }
    }
}
