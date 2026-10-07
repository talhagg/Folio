import SwiftUI

/// Listenin üst bölümü: segmentli tarih filtresi, "N not · filtre" özeti ve kaldırılabilir çipler.
struct DateFilterBar: View {
    @Binding var dateFilter: DateFilter
    let resultCount: Int
    var searchText: String = ""
    var onClearSearch: (() -> Void)? = nil

    @State private var isCustomPopoverShown = false
    @State private var customStart = Date.now
    @State private var customEnd = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s2 + 2) {
            HStack(spacing: Metrics.Spacing.s1) {
                FilterPills(
                    items: [DateFilter.Kind.all, .today, .week, .month].map { .init(value: $0, title: $0.title) },
                    selection: kindBinding
                )
                Spacer(minLength: Metrics.Spacing.s1)
                // Özel aralık: seçiliyken aralığın kendisini gösterir.
                PillButton(
                    title: dateFilter.kind == .custom ? dateFilter.summaryTitle : DateFilter.Kind.custom.title,
                    systemImage: "calendar",
                    isSelected: dateFilter.kind == .custom
                ) {
                    kindBinding.wrappedValue = .custom
                }
                .help(Text("Özel tarih aralığı"))
                .popover(isPresented: $isCustomPopoverShown, arrowEdge: .bottom) {
                    customRangePopover
                }
            }

            HStack(spacing: Metrics.Spacing.s2) {
                Text(summary)
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
                    .lineLimit(1)
                Spacer(minLength: Metrics.Spacing.s2)
                if !searchText.isEmpty, let onClearSearch {
                    FilterChip(title: "“\(searchText)”", onRemove: onClearSearch)
                }
                if dateFilter != .all {
                    FilterChip(title: dateFilter.summaryTitle) {
                        withAnimation(.snappy) { dateFilter = .all }
                    }
                }
            }
            .frame(minHeight: 22)
        }
    }

    private var summary: String {
        if !searchText.isEmpty {
            let results = String(localized: "\(resultCount) sonuç")
            return dateFilter == .all ? String(localized: "\(results) · tüm notlar") : "\(results) · \(dateFilter.summaryTitle)"
        }
        let count = String(localized: "\(resultCount) not")
        return "\(count) · \(dateFilter.summaryTitle)"
    }

    private var kindBinding: Binding<DateFilter.Kind> {
        Binding {
            dateFilter.kind
        } set: { kind in
            switch kind {
            case .all: dateFilter = .all
            case .today: dateFilter = .today
            case .week: dateFilter = .week
            case .month: dateFilter = .month
            case .custom:
                if case .custom(let start, let end) = dateFilter {
                    customStart = start
                    customEnd = end
                } else {
                    let week = DateFilter.week.interval(now: .now)
                    customStart = week?.start ?? .now
                    customEnd = .now
                }
                isCustomPopoverShown = true
            }
        }
    }

    private var customRangePopover: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            Text("Özel aralık")
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
            Grid(alignment: .leading, horizontalSpacing: Metrics.Spacing.s3, verticalSpacing: Metrics.Spacing.s2) {
                GridRow {
                    Text("Başlangıç").textStyle(.callout).foregroundStyle(Color.ds.inkSecondary)
                    DatePicker("Başlangıç", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow {
                    Text("Bitiş").textStyle(.callout).foregroundStyle(Color.ds.inkSecondary)
                    DatePicker("Bitiş", selection: $customEnd, in: customStart..., displayedComponents: .date)
                        .labelsHidden()
                }
            }
            HStack {
                Spacer()
                Button("Vazgeç") { isCustomPopoverShown = false }
                    .keyboardShortcut(.cancelAction)
                Button("Uygula") {
                    dateFilter = .custom(start: customStart, end: customEnd)
                    isCustomPopoverShown = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.Spacing.s4)
        .frame(width: 260)
    }
}

private struct DateFilterBarPreview: View {
    @State private var filter = DateFilter.week

    var body: some View {
        DateFilterBar(dateFilter: $filter, resultCount: 5)
            .padding(Metrics.Spacing.s4)
            .frame(width: Metrics.Layout.listWidth)
            .background(Color.ds.windowBg)
    }
}

#Preview("Light") { DateFilterBarPreview().preferredColorScheme(.light) }
#Preview("Dark") { DateFilterBarPreview().preferredColorScheme(.dark) }
