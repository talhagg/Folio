import SwiftData
import SwiftUI

/// Not satırı: başlık, 2 satır özet, tarih (gecikmişse kırmızı), defter etiketi ve küçük ilerleme.
struct NoteRowView: View {
    let note: Note
    var now: Date = .now
    var isSelected = false
    /// Boş değilse başlık ve önizlemedeki eşleşmeler vurgulanır.
    var searchText = ""
    var onTogglePin: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.Spacing.s2) {
                Text(SearchHighlighter.attributed(
                    note.title.isEmpty ? String(localized: "Başlıksız not") : note.title,
                    query: searchText
                ))
                    .textStyle(.headline)
                    .foregroundStyle(note.title.isEmpty ? Color.ds.inkTertiary : Color.ds.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                pinButton
            }

            let preview = SearchSnippet.preview(
                body: note.body,
                taskTexts: searchText.isEmpty ? [] : note.sortedTasks.map(\.text),
                query: searchText
            )
            if !preview.isEmpty {
                Text(SearchHighlighter.attributed(preview, query: searchText))
                    .textStyle(.callout)
                    .foregroundStyle(Color.ds.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            meta
                .padding(.top, 2)
        }
        .padding(.horizontal, Metrics.Spacing.s3)
        .padding(.vertical, Metrics.Spacing.s2 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
    }

    /// Sabitlenmiş notta dolu iğne (tıklayınca kaldırır); hover'da soluk iğne (tıklayınca sabitler).
    @ViewBuilder
    private var pinButton: some View {
        if !note.isTrashed, let onTogglePin, note.isPinned || isHovered {
            Button(action: onTogglePin) {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(note.isPinned ? Color.ds.inkSecondary : Color.ds.inkTertiary.opacity(0.7))
                    .rotationEffect(.degrees(45))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(note.isPinned ? "Sabitlemeyi kaldır" : "Sabitle"))
            .accessibilityLabel(Text(note.isPinned ? "Sabitlemeyi kaldır" : "Sabitle"))
        } else if note.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.ds.inkTertiary)
                .rotationEffect(.degrees(45))
                .accessibilityLabel(Text("Sabitlenmiş"))
        }
    }

    @ViewBuilder
    private var meta: some View {
        if let deletedAt = note.deletedAt {
            trashMeta(deletedAt: deletedAt)
        } else {
            activeMeta
        }
    }

    private func trashMeta(deletedAt: Date) -> some View {
        let days = Trash.daysRemaining(deletedAt: deletedAt, now: now)
        return HStack(spacing: Metrics.Spacing.s2) {
            Label {
                Text(days == 0 ? "Bugün silinecek" : "\(days) gün kaldı")
            } icon: {
                Image(systemName: "clock")
            }
            .labelStyle(CompactLabelStyle())
            .foregroundStyle(days <= 7 ? Color.ds.statusBlocked : Color.ds.inkSecondary)
            if let path = note.locationPath {
                Text(path)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .lineLimit(1)
            }
        }
        .textStyle(.caption)
    }

    private var activeMeta: some View {
        HStack(spacing: Metrics.Spacing.s2) {
            let isOverdue = note.isOverdue(now: now)
            Text(DateGrouping.rowDateText(for: note.updatedAt, now: now))
                .textStyle(.caption)
                .foregroundStyle(isOverdue ? Color.ds.statusBlocked : Color.ds.inkSecondary)
                .monospacedDigit()
                .accessibilityLabel(isOverdue ? Text("Gecikti, \(DateGrouping.rowDateText(for: note.updatedAt, now: now))") : Text(DateGrouping.rowDateText(for: note.updatedAt, now: now)))
            if let notebook = note.notebook {
                GroupTag(name: notebook.name, color: notebook.color)
                    .layoutPriority(1)
            }
            if let progress = note.progress {
                ProgressBarView(value: progress, size: .sm, tint: progressTint(isOverdue: isOverdue))
                    .frame(minWidth: 48, maxWidth: .infinity)
            } else if note.status == .blocked {
                Spacer(minLength: 0)
                StatusBadge(status: .blocked)
            }
        }
    }

    private struct CompactLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) {
                configuration.icon
                configuration.title
            }
        }
    }

    private func progressTint(isOverdue: Bool) -> Color {
        if isOverdue { return Color.ds.statusBlocked }
        return switch note.status {
        case .todo: Color.ds.statusTodo
        case .doing: Color.ds.statusDoing
        case .done: Color.ds.statusDone
        case .blocked: Color.ds.statusBlocked
        }
    }
}

#if DEBUG
#Preview {
    @MainActor
    struct Wrapper: View {
        let container = SampleData.container()

        var body: some View {
            let notes = (try? container.mainContext.fetch(
                FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            )) ?? []
            VStack(spacing: 2) {
                ForEach(Array(notes.prefix(4).enumerated()), id: \.offset) { index, note in
                    NoteRowView(note: note, isSelected: index == 0)
                        .rowBackground(isSelected: index == 0, cornerRadius: Metrics.Radius.lg)
                }
            }
            .padding(Metrics.Spacing.s2)
            .frame(width: Metrics.Layout.listWidth)
            .background(Color.ds.windowBg)
        }
    }
    return Wrapper()
}
#endif
