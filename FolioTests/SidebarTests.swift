import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct SidebarTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }
    let calendar = Calendar(identifier: .gregorian)
    /// 2026-10-07 12:00 UTC
    let now = Date(timeIntervalSince1970: 1_791_374_400)

    @Test func smartFiltersMatchNotes() {
        let section = context.sectionForNewNote(selection: nil, now: now)
        let todayNote = context.addNote(in: section, title: "Bugün", now: now)
        let oldNote = context.addNote(in: section, title: "Eski", now: now.addingTimeInterval(-86_400 * 3))
        oldNote.isPinned = true
        let dueToday = context.addNote(in: section, title: "Hedef bugün", now: now.addingTimeInterval(-86_400 * 5))
        dueToday.dueDate = now.addingTimeInterval(3600)
        let task1 = NoteTask(text: "a", isDone: true)
        let task2 = NoteTask(text: "b")
        context.insert(task1); context.insert(task2)
        task1.note = oldNote; task2.note = oldNote

        let today = SmartFilter.today
        #expect(today.includes(todayNote, now: now, calendar: calendar))
        #expect(!today.includes(oldNote, now: now, calendar: calendar))
        #expect(today.includes(dueToday, now: now, calendar: calendar))
        #expect(SmartFilter.pinned.includes(oldNote, now: now))
        #expect(!SmartFilter.pinned.includes(todayNote, now: now))
        #expect(SmartFilter.inProgress.includes(oldNote, now: now))
        #expect(!SmartFilter.inProgress.includes(todayNote, now: now))
        #expect([todayNote, oldNote, dueToday].allSatisfy { SmartFilter.all.includes($0, now: now) })
    }

    @Test func notebookAndSectionSelectionMatchHierarchy() {
        let work = context.addNotebook(name: "İş")
        let sprint = context.addSection(name: "Sprint", to: work)
        let meetings = context.addSection(name: "Toplantılar", to: work)
        let home = context.addNotebook(name: "Ev")
        let homeSection = context.addSection(name: "Genel", to: home)
        let a = context.addNote(in: sprint)
        let b = context.addNote(in: meetings)
        let c = context.addNote(in: homeSection)

        let notebookSelection = SidebarSelection.notebook(work.id)
        #expect(notebookSelection.includes(a, now: now))
        #expect(notebookSelection.includes(b, now: now))
        #expect(!notebookSelection.includes(c, now: now))

        let sectionSelection = SidebarSelection.section(sprint.id)
        #expect(sectionSelection.includes(a, now: now))
        #expect(!sectionSelection.includes(b, now: now))
    }

    @Test func addNotebookAppendsSortIndexAndCyclesColors() {
        let first = context.addNotebook(name: "A")
        let second = context.addNotebook(name: "B")
        #expect(second.sortIndex == first.sortIndex + 1)
        #expect(first.color != second.color)
    }

    @Test func addSectionAppendsWithinNotebook() {
        let notebook = context.addNotebook(name: "A")
        let s1 = context.addSection(name: "1", to: notebook)
        let s2 = context.addSection(name: "2", to: notebook)
        #expect(notebook.sortedSections.map(\.name) == ["1", "2"])
        #expect(s2.sortIndex > s1.sortIndex)
    }

    @Test func newNoteSectionCreatesHierarchyWhenEmpty() {
        let section = context.sectionForNewNote(selection: .smart(.all), now: now)
        #expect(section.notebook != nil)
        #expect(((try? context.fetchCount(FetchDescriptor<Notebook>())) ?? 0) == 1)
    }

    @Test func newNoteSectionPrefersSelection() {
        let notebook = context.addNotebook(name: "A")
        _ = context.addSection(name: "1", to: notebook)
        let second = context.addSection(name: "2", to: notebook)
        #expect(context.sectionForNewNote(selection: .section(second.id)) === second)
        #expect(context.sectionForNewNote(selection: .notebook(notebook.id)).name == "1")
    }

    @Test func newNoteSectionAddsSectionToEmptyNotebook() {
        let notebook = context.addNotebook(name: "Boş")
        let section = context.sectionForNewNote(selection: .notebook(notebook.id))
        #expect(section.notebook === notebook)
    }
}

@MainActor
struct SelectionPersistenceTests {
    /// Regresyon: kaydedilmemiş bölüm seçilip kayıttan sonra not eklenince çöküyordu.
    @Test func newNoteInSectionCreatedBeforeSave() throws {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let notebook = context.addNotebook(name: "Yeni")
        let section = context.addSection(name: "Genel", to: notebook)
        let selection = SidebarSelection.section(section.id)
        try context.save()
        let target = context.sectionForNewNote(selection: selection)
        let note = context.addNote(in: target)
        #expect(target === section)
        #expect(selection.includes(note, now: .now))
    }
}
