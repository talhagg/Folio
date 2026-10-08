import SwiftData
import SwiftUI

/// Takvim mantığı (saf): bir günün hedefleri ve ayın dolu günleri.
enum CalendarAgenda {
    enum Item: Identifiable {
        case note(Note)
        case task(NoteTask, Note)

        var id: String {
            switch self {
            case .note(let note): "n-\(note.id)"
            case .task(let task, _): "t-\(task.id)"
            }
        }

        var note: Note {
            switch self {
            case .note(let note), .task(_, let note): note
            }
        }
    }

    static func items(on day: Date, in notes: [Note], calendar: Calendar = .current) -> [Item] {
        var result: [Item] = []
        for note in notes where !note.isTrashed {
            if let due = note.dueDate, calendar.isDate(due, inSameDayAs: day) { result.append(.note(note)) }
            for task in note.sortedTasks {
                if let due = task.dueDate, calendar.isDate(due, inSameDayAs: day) { result.append(.task(task, note)) }
            }
        }
        return result
    }

    /// Ayın içinde hedefi olan günler (gün başlangıcı olarak).
    static func busyDays(inMonthOf month: Date, notes: [Note], calendar: Calendar = .current) -> Set<Date> {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var days = Set<Date>()
        for note in notes where !note.isTrashed {
            let dates = [note.dueDate] + note.sortedTasks.map(\.dueDate)
            for date in dates.compactMap({ $0 }) where interval.contains(date) {
                days.insert(calendar.startOfDay(for: date))
            }
        }
        return days
    }

    /// Ay görünümü için 6 hafta × 7 gün; ilk gün takvimin hafta başlangıcı.
    static func gridDays(for month: Date, calendar: Calendar = .current) -> [Date] {
        guard let first = calendar.dateInterval(of: .month, for: month)?.start,
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: first)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }
}

/// Liste sütununda ay takvimi; seçili günün not ve görev hedefleri altta.
struct CalendarView: View {
    @Binding var selectedNoteID: UUID?
    var now: Date = .now

    @Query private var notes: [Note]
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current

    var body: some View {
        let busy = CalendarAgenda.busyDays(inMonthOf: month, notes: notes, calendar: calendar)
        let items = CalendarAgenda.items(on: selectedDay, in: notes, calendar: calendar)

        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(CalendarAgenda.gridDays(for: month, calendar: calendar), id: \.self) { day in
                    dayCell(day, isBusy: busy.contains(day))
                }
            }
            .padding(.horizontal, Metrics.Spacing.s2)
            .padding(.bottom, Metrics.Spacing.s3)

            Rectangle().fill(Color.ds.separator).frame(height: 1)

            agenda(items)
        }
        .background(Color.ds.windowBg)
    }

    private var monthHeader: some View {
        HStack(spacing: Metrics.Spacing.s1) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
            Spacer()
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .help(Text("Önceki ay"))
            Button("Bugün") {
                month = calendar.startOfDay(for: now)
                selectedDay = calendar.startOfDay(for: now)
            }
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .help(Text("Sonraki ay"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Metrics.Spacing.s3)
        .padding(.top, Metrics.Spacing.s3)
        .padding(.bottom, Metrics.Spacing.s2)
    }

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack(spacing: 2) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Metrics.Spacing.s2)
        .padding(.bottom, Metrics.Spacing.s1)
    }

    private func dayCell(_ day: Date, isBusy: Bool) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.ds.onAccent : (inMonth ? Color.ds.ink : Color.ds.inkTertiary.opacity(0.6)))
                    .frame(width: 26, height: 26)
                    .background {
                        if isSelected {
                            Circle().fill(Color.ds.accent)
                        } else if isToday {
                            Circle().strokeBorder(Color.ds.accent, lineWidth: 1.5)
                        }
                    }
                Circle()
                    .fill(isBusy ? Color.ds.accent : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
        .accessibilityValue(isBusy ? Text("Hedef var") : Text(""))
    }

    private func agenda(_ items: [CalendarAgenda.Item]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay.formatted(.dateTime.day().month(.wide).weekday(.wide)))
                    .textStyle(.sectionLabel)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .padding(.horizontal, Metrics.Spacing.s3)
                    .padding(.top, Metrics.Spacing.s3)
                    .padding(.bottom, Metrics.Spacing.s1)
                if items.isEmpty {
                    Text("Bu gün için hedef yok")
                        .textStyle(.callout)
                        .foregroundStyle(Color.ds.inkSecondary)
                        .padding(.horizontal, Metrics.Spacing.s3)
                        .padding(.vertical, Metrics.Spacing.s2)
                }
                ForEach(items) { item in
                    agendaRow(item)
                }
            }
            .padding(.horizontal, Metrics.Spacing.s2)
            .padding(.bottom, Metrics.Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func agendaRow(_ item: CalendarAgenda.Item) -> some View {
        let isSelected = item.note.id == selectedNoteID
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.s2) {
            switch item {
            case .note(let note):
                StatusBadge(status: note.status, showsTitle: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? String(localized: "Başlıksız not") : note.title)
                        .textStyle(.headline)
                        .foregroundStyle(Color.ds.ink)
                    if let notebook = note.notebook { GroupTag(name: notebook.name, color: notebook.color) }
                }
            case .task(let task, let note):
                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.isDone ? Color.ds.accent : Color.ds.controlBorder)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .textStyle(.body)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? Color.ds.inkTertiary : Color.ds.ink)
                    Text(note.title)
                        .textStyle(.caption)
                        .foregroundStyle(Color.ds.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.Spacing.s2 + 2)
        .padding(.vertical, Metrics.Spacing.s2)
        .rowBackground(isSelected: isSelected, cornerRadius: Metrics.Radius.md)
        .onTapGesture { selectedNoteID = item.note.id }
    }

    private func shiftMonth(_ value: Int) {
        if let shifted = calendar.date(byAdding: .month, value: value, to: month) { month = shifted }
    }
}
