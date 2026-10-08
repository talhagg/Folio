import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct TemplateTests {
    @Test(arguments: NoteTemplate.allCases)
    func templateCreatesStructuredNote(template: NoteTemplate) {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let section = context.sectionForNewNote(selection: nil)
        let note = context.addNote(from: template, in: section, now: TestClock.now)
        #expect(!note.title.isEmpty)
        #expect(note.taskCount == template.tasks.count)
        #expect(note.sortedTasks.map(\.text) == template.tasks)
        let headings = MarkdownDocument.parse(note.body).filter { if case .heading = $0.block { true } else { false } }
        #expect(headings.count >= 2)
    }

    @Test func datedTemplatesIncludeTheDate() {
        #expect(NoteTemplate.daily.noteTitle(now: TestClock.now).contains("2026"))
        #expect(NoteTemplate.meeting.noteTitle(now: TestClock.now).contains("2026"))
    }
}

@MainActor
struct BoardAndCalendarTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }

    private func note(tasks: [Bool] = []) -> Note {
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: "n")
        for (index, done) in tasks.enumerated() {
            let task = NoteTask(text: "\(index)", isDone: done, sortIndex: Double(index))
            context.insert(task)
            task.note = note
        }
        return note
    }

    @Test(arguments: NoteStatus.allCases)
    func noteWithoutTasksTakesAnyStatus(status: NoteStatus) {
        let note = note()
        note.setStatus(status)
        #expect(note.status == status)
    }

    @Test func noteWithTasksMovesByCheckingTasks() {
        let note = note(tasks: [false, false, false])
        note.setStatus(.done)
        #expect(note.status == .done && note.doneTaskCount == 3)
        note.setStatus(.doing)
        #expect(note.status == .doing)
        note.setStatus(.todo)
        #expect(note.status == .todo && note.doneTaskCount == 0)
        note.setStatus(.doing)
        #expect(note.status == .doing && note.doneTaskCount == 1)
        note.setStatus(.blocked)
        #expect(note.status == .blocked)
        note.setStatus(.todo)
        #expect(note.status == .todo && !note.isBlocked)
    }

    @Test func calendarCollectsNoteAndTaskDueDates() {
        let calendar = TestClock.calendar
        let day = TestClock.date(daysAgo: -2)
        let a = note()
        a.dueDate = day
        let b = note(tasks: [false])
        b.sortedTasks[0].dueDate = day.addingTimeInterval(3600)
        let trashed = note()
        trashed.dueDate = day
        context.moveToTrash(trashed)
        let items = CalendarAgenda.items(on: day, in: [a, b, trashed], calendar: calendar)
        #expect(items.count == 2)
        let busy = CalendarAgenda.busyDays(inMonthOf: day, notes: [a, b], calendar: calendar)
        #expect(busy == [calendar.startOfDay(for: day)])
    }

    @Test func monthGridStartsOnWeekStartAndHas42Days() {
        let calendar = TestClock.calendar
        let days = CalendarAgenda.gridDays(for: TestClock.now, calendar: calendar)
        #expect(days.count == 42)
        #expect(calendar.component(.weekday, from: days[0]) == calendar.firstWeekday)
        #expect(days.contains { calendar.isDate($0, inSameDayAs: TestClock.now) })
    }
}
