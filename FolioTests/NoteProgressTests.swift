import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct NoteProgressTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    private func makeNote(tasks: [Bool], dueDate: Date? = nil) -> Note {
        let note = Note(title: "Test", createdAt: now, dueDate: dueDate)
        context.insert(note)
        for (index, isDone) in tasks.enumerated() {
            let task = NoteTask(text: "Görev \(index)", isDone: isDone, sortIndex: Double(index))
            context.insert(task)
            task.note = note
        }
        return note
    }

    @Test func progressIsNilWithoutTasks() {
        let note = makeNote(tasks: [])
        #expect(note.progress == nil)
        #expect(note.status == .todo)
    }

    @Test func progressIsDoneOverTotal() {
        let note = makeNote(tasks: [true, true, true, true, true, false, false, false])
        #expect(note.progress == 5.0 / 8.0)
        #expect(note.doneTaskCount == 5)
        #expect(note.taskCount == 8)
    }

    @Test(arguments: [
        ([false, false], NoteStatus.todo),
        ([true, false], NoteStatus.doing),
        ([true, true], NoteStatus.done),
    ])
    func statusFollowsProgress(tasks: [Bool], expected: NoteStatus) {
        #expect(makeNote(tasks: tasks).status == expected)
    }

    @Test func blockedOverrideWinsOverProgress() {
        let note = makeNote(tasks: [true, true])
        note.isBlocked = true
        #expect(note.status == .blocked)
        #expect(note.statusOverrideRaw == "blocked")
        note.isBlocked = false
        #expect(note.statusOverrideRaw == nil)
        #expect(note.status == .done)
    }

    @Test func sortedTasksUseSortIndex() {
        let note = makeNote(tasks: [false, false, false])
        note.sortedTasks.last?.sortIndex = -1
        #expect(note.sortedTasks.first?.text == "Görev 2")
    }

    @Test func overdueWhenDuePassedAndNotDone() {
        let note = makeNote(tasks: [true, false], dueDate: now.addingTimeInterval(-60))
        #expect(note.isOverdue(now: now))
    }

    @Test func notOverdueWhenDone() {
        let note = makeNote(tasks: [true], dueDate: now.addingTimeInterval(-60))
        #expect(!note.isOverdue(now: now))
    }

    @Test func notOverdueWhenDueInFutureOrMissing() {
        #expect(!makeNote(tasks: [false], dueDate: now.addingTimeInterval(60)).isOverdue(now: now))
        #expect(!makeNote(tasks: [false]).isOverdue(now: now))
    }

    @Test func touchUpdatesUpdatedAt() {
        let note = makeNote(tasks: [])
        let later = now.addingTimeInterval(3600)
        note.touch(now: later)
        #expect(note.updatedAt == later)
    }

    @Test func statusResolveMatrix() {
        #expect(NoteStatus.resolve(progress: nil, overrideRaw: nil) == .todo)
        #expect(NoteStatus.resolve(progress: 0, overrideRaw: nil) == .todo)
        #expect(NoteStatus.resolve(progress: 0.5, overrideRaw: nil) == .doing)
        #expect(NoteStatus.resolve(progress: 1, overrideRaw: nil) == .done)
        #expect(NoteStatus.resolve(progress: 1, overrideRaw: "blocked") == .blocked)
        #expect(NoteStatus.resolve(progress: 0.5, overrideRaw: "bilinmeyen") == .doing)
    }
}

@MainActor
struct SampleDataTests {
    @Test func insertsFourNotebooksFifteenActiveAndTwoTrashedNotes() throws {
        let container = SampleData.container()
        let context = container.mainContext
        let notebooks = try context.fetch(FetchDescriptor<Notebook>())
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notebooks.count == 4)
        #expect(notes.count(where: { !$0.isTrashed }) == 15)
        #expect(notes.count(where: \.isTrashed) == 2)
        #expect(notes.allSatisfy { $0.section?.notebook != nil })
    }
}

@MainActor
struct TaskOperationTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }
    let now = TestClock.now

    private func makeNote(_ texts: [String]) -> Note {
        let note = Note(title: "Not", createdAt: now.addingTimeInterval(-3600))
        context.insert(note)
        for text in texts { note.addTask(text: text, in: context, now: now.addingTimeInterval(-3600)) }
        return note
    }

    @Test func addAppendsAndInsertsAfterAnchor() {
        let note = makeNote(["a", "c"])
        note.addTask(text: "b", after: note.sortedTasks[0], in: context, now: now)
        #expect(note.sortedTasks.map(\.text) == ["a", "b", "c"])
        #expect(note.sortedTasks.map(\.sortIndex) == [0, 1, 2])
        #expect(note.updatedAt == now)
    }

    @Test func removeReindexes() {
        let note = makeNote(["a", "b", "c"])
        note.removeTask(note.sortedTasks[1], in: context, now: now)
        #expect(note.sortedTasks.map(\.text) == ["a", "c"])
        #expect(note.sortedTasks.map(\.sortIndex) == [0, 1])
    }

    @Test func moveBeforeTargetAndToEnd() {
        let note = makeNote(["a", "b", "c"])
        let ids = note.sortedTasks.map(\.id)
        note.moveTask(ids[2], before: ids[0], now: now)
        #expect(note.sortedTasks.map(\.text) == ["c", "a", "b"])
        note.moveTask(ids[2], before: nil, now: now)
        #expect(note.sortedTasks.map(\.text) == ["a", "b", "c"])
    }

    @Test func toggleTouchesNote() {
        let note = makeNote(["a"])
        note.toggle(note.sortedTasks[0], now: now)
        #expect(note.progress == 1)
        #expect(note.updatedAt == now)
    }

    @Test func orderingIsPure() {
        #expect(Reordering.move([1, 2, 3], item: 1, before: 3) == [2, 1, 3])
        #expect(Reordering.move([1, 2, 3], item: 2, before: 2) == [1, 2, 3])
        #expect(Reordering.move([1, 2, 3], item: 9, before: 1) == [1, 2, 3])
    }

    @Test func editorDateText() {
        let calendar = TestClock.calendar
        #expect(DateGrouping.editorDateText(for: TestClock.date(daysAgo: 0, hour: 9, minute: 5), now: now, calendar: calendar) == "bugün 09:05")
        #expect(DateGrouping.editorDateText(for: TestClock.date(daysAgo: 1, hour: 14, minute: 32), now: now, calendar: calendar) == "dün 14:32")
        #expect(DateGrouping.editorDateText(for: TestClock.date(daysAgo: 2), now: now, calendar: calendar) == "5 Eki")
    }
}
