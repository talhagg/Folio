import Foundation
import SwiftData
import Testing
@testable import Folio

struct DateGroupingTests {
    let now = TestClock.now
    let calendar = TestClock.calendar

    @Test(arguments: [
        (0, DateGroup.today),       // Çar 7 Eki
        (1, DateGroup.yesterday),   // Sal 6 Eki
        (2, DateGroup.thisWeek),    // Pzt 5 Eki
        (3, DateGroup.thisMonth),   // Paz 4 Eki — hafta Pazartesi başlar
        (6, DateGroup.thisMonth),   // Per 1 Eki
        (7, DateGroup.older),       // Çar 30 Eyl
    ])
    func groupForDaysAgo(days: Int, expected: DateGroup) {
        #expect(DateGroup.of(TestClock.date(daysAgo: days), now: now, calendar: calendar) == expected)
    }

    @Test func weekStartFollowsCalendar() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let sunday = TestClock.date(daysAgo: 3)
        #expect(DateGroup.of(sunday, now: now, calendar: sundayFirst) == .thisWeek)
    }

    @Test func futureDatesCountAsToday() {
        #expect(DateGroup.of(now.addingTimeInterval(86_400 * 3), now: now, calendar: calendar) == .today)
    }

    @Test func rowDateTextFormats() {
        #expect(DateGrouping.rowDateText(for: TestClock.date(daysAgo: 0, hour: 10, minute: 5), now: now, calendar: calendar) == "10:05")
        #expect(DateGrouping.rowDateText(for: TestClock.date(daysAgo: 1), now: now, calendar: calendar) == "Dün")
        #expect(DateGrouping.rowDateText(for: TestClock.date(daysAgo: 2), now: now, calendar: calendar) == "Pzt")
        #expect(DateGrouping.rowDateText(for: TestClock.date(daysAgo: 6), now: now, calendar: calendar) == "1 Eki")
        #expect(DateGrouping.rowDateText(for: TestClock.date(daysAgo: 400), now: now, calendar: calendar).contains("2025"))
    }

    @MainActor
    @Test func groupsPutPinnedFirstAndSortNewestFirst() {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        func note(_ title: String, daysAgo: Int, hour: Int = 10, pinned: Bool = false) -> Note {
            let note = Note(title: title, createdAt: TestClock.date(daysAgo: daysAgo, hour: hour), isPinned: pinned)
            context.insert(note)
            return note
        }
        let notes = [
            note("eski", daysAgo: 30),
            note("bugün sabah", daysAgo: 0, hour: 8),
            note("sabit", daysAgo: 20, pinned: true),
            note("bugün öğle", daysAgo: 0, hour: 11),
            note("dün", daysAgo: 1),
        ]
        let groups = DateGrouping.groups(for: notes, now: now, calendar: calendar)
        #expect(groups.map(\.group) == [.pinned, .today, .yesterday, .older])
        #expect(groups[1].notes.map(\.title) == ["bugün öğle", "bugün sabah"])
    }

    @Test func markdownPreviewStripsSyntax() {
        let markdown = "# Başlık\n\n- [x] Görev\n**Kalın** ve `kod`\n> alıntı"
        #expect(MarkdownPreview.plainText(markdown) == "Başlık Görev Kalın ve kod alıntı")
    }
}
