import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct TrashTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }
    let now = TestClock.now
    let calendar = TestClock.calendar

    private func makeNote(_ title: String = "Not", in section: NoteSection? = nil) -> Note {
        let section = section ?? context.sectionForNewNote(selection: nil, now: now)
        return context.addNote(in: section, title: title, now: now.addingTimeInterval(-3600))
    }

    @Test func trashedNoteLeavesEveryViewButTrash() throws {
        let note = makeNote()
        note.isPinned = true
        context.moveToTrash(note, now: now)
        #expect(note.isTrashed)
        #expect(note.trashedFromPath == "Notlarım › Genel")
        for filter in SmartFilter.allCases {
            #expect(!SidebarSelection.smart(filter).includes(note, now: now))
        }
        #expect(SidebarSelection.trash.includes(note, now: now))
        #expect(note.section?.activeNotes.isEmpty == true)

        let trashFilter = NoteFilter(selection: .trash, now: now, calendar: calendar)
        #expect(try trashFilter.apply(to: context.fetch(trashFilter.descriptor)).map(\.id) == [note.id])
        let allFilter = NoteFilter(selection: .smart(.all), now: now, calendar: calendar)
        #expect(try allFilter.apply(to: context.fetch(allFilter.descriptor)).isEmpty)
    }

    @Test func globalSearchSkipsTrashButTrashSearchFindsIt() throws {
        let kept = makeNote("Rapor taslağı")
        let trashed = makeNote("Rapor eski")
        context.moveToTrash(trashed, now: now)
        let global = NoteFilter(selection: .smart(.all), searchText: "rapor", now: now, calendar: calendar)
        #expect(try global.apply(to: context.fetch(global.descriptor)).map(\.id) == [kept.id])
        let inTrash = NoteFilter(selection: .trash, searchText: "rapor", now: now, calendar: calendar)
        #expect(try inTrash.apply(to: context.fetch(inTrash.descriptor)).map(\.id) == [trashed.id])
    }

    @Test func restoreReturnsToOriginalSection() {
        let note = makeNote()
        let section = note.section
        context.moveToTrash(note, now: now)
        context.restore(note, now: now)
        #expect(!note.isTrashed)
        #expect(note.section === section)
        #expect(note.trashedFromPath == nil)
    }

    @Test func deletingSectionKeepsNotesInTrashAndRestoreFallsBack() {
        let notebook = context.addNotebook(name: "İş")
        let doomed = context.addSection(name: "Eski", to: notebook)
        let keeper = context.addSection(name: "Yeni", to: notebook)
        let note = makeNote("Kurtarılacak", in: doomed)

        context.trashSection(doomed, now: now)
        #expect(note.isTrashed)
        #expect(note.section == nil)
        #expect(note.locationPath == "İş › Eski")

        context.restore(note, now: now)
        #expect(note.section === keeper)
    }

    @Test func purgeDeletesOnlyExpiredNotes() throws {
        let old = makeNote("Eski")
        let recent = makeNote("Yeni")
        context.moveToTrash(old, now: now.addingTimeInterval(-86_400 * 91))
        context.moveToTrash(recent, now: now.addingTimeInterval(-86_400 * 89))
        let purged = context.purgeExpiredTrash(now: now, calendar: calendar)
        try context.save()
        #expect(purged == 1)
        let remaining = try context.fetch(FetchDescriptor<Note>()).map(\.title)
        #expect(remaining == ["Yeni"])
    }

    @Test func daysRemainingCountsDownFromNinety() {
        #expect(Trash.daysRemaining(deletedAt: now, now: now, calendar: calendar) == 90)
        #expect(Trash.daysRemaining(deletedAt: TestClock.date(daysAgo: 80), now: now, calendar: calendar) == 10)
        #expect(Trash.daysRemaining(deletedAt: TestClock.date(daysAgo: 120), now: now, calendar: calendar) == 0)
    }

    @Test func movingTrashedNoteToSectionRestoresIt() {
        let note = makeNote()
        let target = context.addSection(name: "Hedef", to: context.addNotebook(name: "Başka"))
        context.moveToTrash(note, now: now)
        context.moveNote(note, to: target, now: now)
        #expect(!note.isTrashed)
        #expect(note.section === target)
    }

    @Test func emptyTrashRemovesAllTrashed() throws {
        let a = makeNote("a"), b = makeNote("b")
        _ = makeNote("c")
        context.moveToTrash(a, now: now)
        context.moveToTrash(b, now: now)
        context.emptyTrash()
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Note>()).map(\.title) == ["c"])
    }
}

@MainActor
struct ReorderTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }

    @Test func moveNotebookBeforeAnother() {
        let a = context.addNotebook(name: "A"), b = context.addNotebook(name: "B"), c = context.addNotebook(name: "C")
        context.moveNotebook(c, before: a)
        #expect([a, b, c].sorted { $0.sortIndex < $1.sortIndex }.map(\.name) == ["C", "A", "B"])
        context.moveNotebook(c, before: nil)
        #expect([a, b, c].sorted { $0.sortIndex < $1.sortIndex }.map(\.name) == ["A", "B", "C"])
    }

    @Test func moveSectionWithinAndAcrossNotebooks() {
        let work = context.addNotebook(name: "İş"), home = context.addNotebook(name: "Ev")
        let s1 = context.addSection(name: "1", to: work)
        let s2 = context.addSection(name: "2", to: work)
        let s3 = context.addSection(name: "3", to: home)
        context.moveSection(s2, to: work, before: s1)
        #expect(work.sortedSections.map(\.name) == ["2", "1"])
        context.moveSection(s1, to: home, before: s3)
        #expect(home.sortedSections.map(\.name) == ["1", "3"])
        #expect(work.sortedSections.map(\.name) == ["2"])
    }

    @Test func moveNoteChangesSection() {
        let notebook = context.addNotebook(name: "İş")
        let from = context.addSection(name: "A", to: notebook), to = context.addSection(name: "B", to: notebook)
        let note = context.addNote(in: from, title: "x")
        context.moveNote(note, to: to)
        #expect(note.section === to)
        #expect(from.activeNotes.isEmpty)
    }

    @Test func dragPayloadRoundTrips() {
        let id = UUID()
        for payload in [DragPayload.note(id), .task(id), .notebook(id), .section(id)] {
            #expect(DragPayload(string: payload.string) == payload)
        }
        #expect(DragPayload(string: id.uuidString) == nil)
        #expect(DragPayload(string: "folio.unknown:\(id.uuidString)") == nil)
    }
}

struct SwipeDecisionTests {
    @Test(arguments: [
        (0.0, SwipeDecision.close),
        (-20.0, SwipeDecision.close),
        (-38.0, SwipeDecision.reveal),
        (-120.0, SwipeDecision.reveal),
        (-200.0, SwipeDecision.delete),
        (-260.0, SwipeDecision.delete),
    ])
    func resolvesByDistance(offset: Double, expected: SwipeDecision) {
        #expect(SwipeDecision.resolve(offset: CGFloat(offset)) == expected)
    }
}
