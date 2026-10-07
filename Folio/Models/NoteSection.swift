import Foundation
import SwiftData

/// `SwiftUI.Section` ile çakışmaması için `NoteSection`.
@Model
final class NoteSection {
    var id: UUID = UUID()
    var name: String = ""
    var sortIndex: Double = 0
    var createdAt: Date = Date.now
    var notebook: Notebook?

    @Relationship(deleteRule: .cascade, inverse: \Note.section)
    var notes: [Note]? = []

    /// Çöpte olmayan notlar.
    var activeNotes: [Note] { (notes ?? []).filter { !$0.isTrashed } }

    init(name: String, sortIndex: Double = 0, createdAt: Date = .now) {
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
