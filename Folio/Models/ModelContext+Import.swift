import Foundation
import SwiftData

extension ModelContext {
    static var importNotebookName: String { String(localized: "İçe Aktarılanlar") }

    /// Belgeleri "İçe Aktarılanlar" defterinde kaynağa özel yeni bir bölüme not olarak ekler.
    @discardableResult
    func importDocuments(_ documents: [ImportedDocument], sourceName: String, now: Date = .now) -> NoteSection? {
        guard !documents.isEmpty else { return nil }
        let notebookName = Self.importNotebookName
        let notebooks = (try? fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.name == notebookName }))) ?? []
        let notebook = notebooks.first ?? addNotebook(name: notebookName, color: .slate, now: now)

        let existingNames = Set((notebook.sections ?? []).map(\.name))
        var sectionName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if sectionName.isEmpty { sectionName = String(localized: "İçe aktarma") }
        if existingNames.contains(sectionName) {
            var counter = 2
            while existingNames.contains("\(sectionName) (\(counter))") { counter += 1 }
            sectionName = "\(sectionName) (\(counter))"
        }
        let section = addSection(name: sectionName, to: notebook, now: now)

        for document in documents {
            let date = document.createdAt ?? now
            let note = addNote(in: section, title: document.title, now: date)
            note.body = document.markdown
            note.isPinned = document.isPinned
            note.dueDate = document.dueDate
            for (index, task) in document.tasks.enumerated() {
                let noteTask = NoteTask(text: task.text, isDone: task.isDone, dueDate: task.dueDate, sortIndex: Double(index))
                insert(noteTask)
                noteTask.note = note
            }
            note.updatedAt = date
        }
        return section
    }
}
