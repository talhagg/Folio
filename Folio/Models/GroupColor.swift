import SwiftUI

/// Defter rengi. Yalnızca nokta/ikon için kullanılır; yanında her zaman defter adı yazar.
enum GroupColor: String, CaseIterable, Codable, Sendable {
    case clay, amber, moss, teal, slate, plum

    var color: Color {
        switch self {
        case .clay: Color.ds.groupClay
        case .amber: Color.ds.groupAmber
        case .moss: Color.ds.groupMoss
        case .teal: Color.ds.groupTeal
        case .slate: Color.ds.groupSlate
        case .plum: Color.ds.groupPlum
        }
    }

    var title: String {
        switch self {
        case .clay: String(localized: "Kil")
        case .amber: String(localized: "Kehribar")
        case .moss: String(localized: "Yosun")
        case .teal: String(localized: "Deniz")
        case .slate: String(localized: "Arduvaz")
        case .plum: String(localized: "Erik")
        }
    }
}
