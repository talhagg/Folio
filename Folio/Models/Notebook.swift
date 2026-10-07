import Foundation
import SwiftData

@Model
final class Notebook {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String = GroupColor.clay.rawValue
    var sortIndex: Double = 0
    var createdAt: Date = Date.now

    // SwiftData inverse'i tek tarafta ister; iki tarafta da yazmak makro döngüsü yaratır.
    @Relationship(deleteRule: .cascade, inverse: \NoteSection.notebook)
    var sections: [NoteSection]? = []

    init(name: String, color: GroupColor = .clay, sortIndex: Double = 0, createdAt: Date = .now) {
        self.name = name
        self.colorRaw = color.rawValue
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    var color: GroupColor {
        get { GroupColor(rawValue: colorRaw) ?? .clay }
        set { colorRaw = newValue.rawValue }
    }

    var sortedSections: [NoteSection] {
        (sections ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Çöpte olmayan notlar.
    var activeNotes: [Note] {
        (sections ?? []).flatMap(\.activeNotes)
    }
}
