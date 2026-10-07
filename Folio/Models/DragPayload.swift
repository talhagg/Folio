import Foundation

/// Sürükle-bırak yükü. Not, görev, defter ve bölüm aynı `String` taşıyıcıyı kullandığından türü önek olarak taşır.
enum DragPayload: Equatable, Sendable {
    case note(UUID)
    case task(UUID)
    case notebook(UUID)
    case section(UUID)

    var string: String {
        switch self {
        case .note(let id): "folio.note:\(id.uuidString)"
        case .task(let id): "folio.task:\(id.uuidString)"
        case .notebook(let id): "folio.notebook:\(id.uuidString)"
        case .section(let id): "folio.section:\(id.uuidString)"
        }
    }

    init?(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "folio.note": self = .note(id)
        case "folio.task": self = .task(id)
        case "folio.notebook": self = .notebook(id)
        case "folio.section": self = .section(id)
        default: return nil
        }
    }
}
