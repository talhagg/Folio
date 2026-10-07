import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct NoteFilterTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }
    let now = TestClock.now
    let calendar = TestClock.calendar

    private func makeLibrary() -> (work: Notebook, sprint: NoteSection, home: NoteSection) {
        let work = context.addNotebook(name: "İş")
        let sprint = context.addSection(name: "Sprint", to: work)
        let home = context.addSection(name: "Ev", to: context.addNotebook(name: "Kişisel"))
        return (work, sprint, home)
    }

    private func note(_ title: String, in section: NoteSection, daysAgo: Int, body: String = "", tasks: [String] = []) -> Note {
        let note = context.addNote(in: section, title: title, now: TestClock.date(daysAgo: daysAgo))
        note.body = body
        for (index, text) in tasks.enumerated() {
            let task = NoteTask(text: text, sortIndex: Double(index))
            context.insert(task)
            task.note = note
        }
        return note
    }

    private func run(_ filter: NoteFilter) throws -> [String] {
        try filter.apply(to: context.fetch(filter.descriptor)).map(\.title)
    }

    @Test func weekFilterUsesLocaleWeekStart() throws {
        let lib = makeLibrary()
        _ = note("çarşamba", in: lib.sprint, daysAgo: 0)
        _ = note("pazartesi", in: lib.sprint, daysAgo: 2)
        _ = note("pazar", in: lib.sprint, daysAgo: 3)
        let filter = NoteFilter(selection: .smart(.all), dateFilter: .week, now: now, calendar: calendar)
        #expect(try run(filter) == ["çarşamba", "pazartesi"])
    }

    @Test func todayAndMonthFilters() throws {
        let lib = makeLibrary()
        _ = note("bugün", in: lib.sprint, daysAgo: 0)
        _ = note("ay başı", in: lib.sprint, daysAgo: 6)
        _ = note("geçen ay", in: lib.sprint, daysAgo: 7)
        #expect(try run(NoteFilter(dateFilter: .today, now: now, calendar: calendar)) == ["bugün"])
        #expect(try run(NoteFilter(dateFilter: .month, now: now, calendar: calendar)) == ["bugün", "ay başı"])
        #expect(try run(NoteFilter(dateFilter: .all, now: now, calendar: calendar)).count == 3)
    }

    @Test func customRangeIncludesWholeEndDay() throws {
        let lib = makeLibrary()
        _ = note("1", in: lib.sprint, daysAgo: 1)
        _ = note("2", in: lib.sprint, daysAgo: 3)
        _ = note("3", in: lib.sprint, daysAgo: 5)
        // Bitiş gününün sabahı verilse de gün sonuna kadar dahil.
        let range = DateFilter.custom(start: TestClock.date(daysAgo: 3, hour: 23), end: TestClock.date(daysAgo: 1, hour: 0))
        #expect(try run(NoteFilter(dateFilter: range, now: now, calendar: calendar)) == ["1", "2"])
    }

    @Test func notebookAndSectionPredicates() throws {
        let lib = makeLibrary()
        let meetings = context.addSection(name: "Toplantı", to: lib.work)
        _ = note("sprint", in: lib.sprint, daysAgo: 0)
        _ = note("toplantı", in: meetings, daysAgo: 1)
        _ = note("ev", in: lib.home, daysAgo: 2)
        #expect(try run(NoteFilter(selection: .notebook(lib.work.id), now: now, calendar: calendar)) == ["sprint", "toplantı"])
        #expect(try run(NoteFilter(selection: .section(meetings.id), now: now, calendar: calendar)) == ["toplantı"])
    }

    @Test func pinnedAndInProgressSmartFilters() throws {
        let lib = makeLibrary()
        let pinned = note("sabit", in: lib.sprint, daysAgo: 0)
        pinned.isPinned = true
        let doing = note("yarım", in: lib.sprint, daysAgo: 1, tasks: ["a", "b"])
        doing.sortedTasks[0].isDone = true
        _ = note("boş", in: lib.sprint, daysAgo: 2)
        #expect(try run(NoteFilter(selection: .smart(.pinned), now: now, calendar: calendar)) == ["sabit"])
        #expect(try run(NoteFilter(selection: .smart(.inProgress), now: now, calendar: calendar)) == ["yarım"])
    }

    @Test func searchMatchesTitleBodyAndTasks() throws {
        let lib = makeLibrary()
        _ = note("Sprint planı", in: lib.sprint, daysAgo: 0)
        _ = note("Gövde", in: lib.sprint, daysAgo: 1, body: "Token yenileme için interceptor")
        _ = note("Görevli", in: lib.sprint, daysAgo: 2, tasks: ["Keychain ile oturum saklama"])
        _ = note("Alakasız", in: lib.sprint, daysAgo: 3)
        func search(_ text: String) throws -> [String] {
            try run(NoteFilter(searchText: text, now: now, calendar: calendar))
        }
        #expect(try search("sprint") == ["Sprint planı"])
        #expect(try search("INTERCEPTOR") == ["Gövde"])
        #expect(try search("keychain") == ["Görevli"])
        #expect(try search("   ").count == 4)
    }

    @Test func selectionAndDateCombine() throws {
        let lib = makeLibrary()
        _ = note("iş bugün", in: lib.sprint, daysAgo: 0)
        _ = note("iş eski", in: lib.sprint, daysAgo: 10)
        _ = note("ev bugün", in: lib.home, daysAgo: 0)
        let filter = NoteFilter(selection: .notebook(lib.work.id), dateFilter: .week, now: now, calendar: calendar)
        #expect(try run(filter) == ["iş bugün"])
    }

    @Test func searchIsGlobalButKeepsDateFilter() throws {
        let lib = makeLibrary()
        _ = note("iş bugün api", in: lib.sprint, daysAgo: 0)
        _ = note("iş eski api", in: lib.sprint, daysAgo: 10)
        _ = note("ev dün api", in: lib.home, daysAgo: 1)
        _ = note("ev bugün", in: lib.home, daysAgo: 0)
        let filter = NoteFilter(
            selection: .notebook(lib.work.id), dateFilter: .week, searchText: "api", now: now, calendar: calendar
        )
        #expect(filter.isSearching)
        #expect(try run(filter) == ["iş bugün api", "ev dün api"])
    }
}
