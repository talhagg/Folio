import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct ReminderTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }
    let calendar = TestClock.calendar
    let now = TestClock.now   // 7 Ekim 12:00 UTC

    private func note(_ title: String, due daysFromNow: Int?, tasks: [(Bool, Int?)] = []) -> Note {
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: title)
        note.dueDate = daysFromNow.map { TestClock.date(daysAgo: -$0, hour: 0) }
        for (index, (done, due)) in tasks.enumerated() {
            let task = NoteTask(text: "Görev \(index)", isDone: done, dueDate: due.map { TestClock.date(daysAgo: -$0, hour: 0) }, sortIndex: Double(index))
            context.insert(task)
            task.note = note
        }
        return note
    }

    @Test func plansFutureNoteAndTaskRemindersAtTheHour() {
        let a = note("Yarın", due: 1)
        let b = note("Görevli", due: nil, tasks: [(false, 2), (true, 2), (false, nil)])
        let planned = Reminders.plan(notes: [a, b], now: now, hour: 9, calendar: calendar)
        #expect(planned.map(\.title) == ["Yarın", "Görev 0"])
        #expect(calendar.component(.hour, from: planned[0].fireDate) == 9)
        #expect(calendar.isDate(planned[0].fireDate, inSameDayAs: TestClock.date(daysAgo: -1)))
        #expect(planned[1].taskID == b.sortedTasks[0].id)
    }

    @Test func skipsPastDoneAndTrashed() {
        let past = note("Geçti", due: -1)
        let todayPastHour = note("Bugün 9 geçti", due: 0)   // saat 12:00, 09:00 geçti
        let done = note("Bitti", due: 3, tasks: [(true, nil)])
        let trashed = note("Çöp", due: 3)
        context.moveToTrash(trashed)
        #expect(Reminders.plan(notes: [past, todayPastHour, done, trashed], now: now, hour: 9, calendar: calendar).isEmpty)
        // Aynı gün ama saat henüz gelmediyse planlanır.
        #expect(Reminders.plan(notes: [todayPastHour], now: now, hour: 18, calendar: calendar).count == 1)
    }

    @Test func limitsToNearestReminders() {
        let notes = (1...80).map { (day: Int) in note("N\(day)", due: day) }
        let planned = Reminders.plan(notes: notes, now: now, hour: 9, calendar: calendar)
        #expect(planned.count == Reminders.maxPending)
        #expect(planned.first?.title == "N1")
    }

    @Test func identifiersAreStablePerItem() {
        let a = note("A", due: 1)
        let first = Reminders.plan(notes: [a], now: now, hour: 9, calendar: calendar)
        let second = Reminders.plan(notes: [a], now: now, hour: 9, calendar: calendar)
        #expect(first.map(\.identifier) == second.map(\.identifier))
        #expect(first[0].identifier.hasPrefix(Reminders.identifierPrefix))
    }
}
