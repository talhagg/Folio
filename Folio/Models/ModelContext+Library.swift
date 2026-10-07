import Foundation
import SwiftData

/// Defter / bölüm / not oluşturma işlemleri. `sortIndex` her zaman mevcut en büyüğün bir fazlasıdır.
extension ModelContext {
    @discardableResult
    func addNotebook(name: String, color: GroupColor? = nil, now: Date = .now) -> Notebook {
        let existing = (try? fetch(FetchDescriptor<Notebook>())) ?? []
        let nextIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        let palette = GroupColor.allCases
        let notebook = Notebook(
            name: name,
            color: color ?? palette[existing.count % palette.count],
            sortIndex: nextIndex,
            createdAt: now
        )
        insert(notebook)
        return notebook
    }

    @discardableResult
    func addSection(name: String, to notebook: Notebook, now: Date = .now) -> NoteSection {
        let nextIndex = ((notebook.sections ?? []).map(\.sortIndex).max() ?? -1) + 1
        let section = NoteSection(name: name, sortIndex: nextIndex, createdAt: now)
        insert(section)
        section.notebook = notebook
        return section
    }

    @discardableResult
    func addNote(in section: NoteSection, title: String = "", now: Date = .now) -> Note {
        let note = Note(title: title, createdAt: now)
        insert(note)
        note.section = section
        return note
    }

    /// Yeni notun gideceği bölüm: seçili bölüm → seçili defterin ilk bölümü → ilk defterin ilk bölümü.
    /// Gerekirse defter ve/veya bölüm oluşturur.
    func sectionForNewNote(selection: SidebarSelection?, now: Date = .now) -> NoteSection {
        switch selection {
        case .section(let id):
            if let section = first(NoteSection.self, id: id) { return section }
        case .notebook(let id):
            if let notebook = first(Notebook.self, id: id) {
                return notebook.sortedSections.first ?? addSection(name: String(localized: "Genel"), to: notebook, now: now)
            }
        default:
            break
        }
        let notebooks = (try? fetch(FetchDescriptor<Notebook>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let notebook = notebooks.first ?? addNotebook(name: String(localized: "Notlarım"), now: now)
        return notebook.sortedSections.first ?? addSection(name: String(localized: "Genel"), to: notebook, now: now)
    }

    // MARK: - Taşıma ve sıralama

    func moveNote(_ note: Note, to section: NoteSection, now: Date = .now) {
        if note.isTrashed {
            note.section = section
            restore(note, now: now)
            return
        }
        guard note.section !== section else { return }
        note.section = section
        note.touch(now: now)
    }

    func moveNotebook(_ notebook: Notebook, before target: Notebook?) {
        let notebooks = (try? fetch(FetchDescriptor<Notebook>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let ids = Reordering.move(notebooks.map(\.id), item: notebook.id, before: target?.id)
        let byID = Dictionary(uniqueKeysWithValues: notebooks.map { ($0.id, $0) })
        for (index, id) in ids.enumerated() { byID[id]?.sortIndex = Double(index) }
    }

    /// Bölümü `notebook` içinde `target`'ın önüne (yoksa sona) taşır; gerekirse defter değiştirir.
    func moveSection(_ section: NoteSection, to notebook: Notebook, before target: NoteSection?) {
        if section.notebook !== notebook {
            section.notebook = notebook
        }
        var ordered = notebook.sortedSections
        if !ordered.contains(where: { $0 === section }) { ordered.append(section) }
        let ids = Reordering.move(ordered.map(\.id), item: section.id, before: target?.id)
        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        for (index, id) in ids.enumerated() { byID[id]?.sortIndex = Double(index) }
    }

    func first(_: Notebook.Type, id: UUID) -> Notebook? {
        var descriptor = FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func first(_: Note.Type, id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func first(_: NoteSection.Type, id: UUID) -> NoteSection? {
        var descriptor = FetchDescriptor<NoteSection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }
}
