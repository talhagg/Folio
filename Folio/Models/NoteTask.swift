import Foundation
import SwiftData

@Model
final class NoteTask {
    var id: UUID = UUID()
    var text: String = ""
    var isDone: Bool = false
    var dueDate: Date?
    var sortIndex: Double = 0
    var note: Note?

    init(text: String, isDone: Bool = false, dueDate: Date? = nil, sortIndex: Double = 0) {
        self.text = text
        self.isDone = isDone
        self.dueDate = dueDate
        self.sortIndex = sortIndex
    }
}
