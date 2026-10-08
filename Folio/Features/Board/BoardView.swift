import SwiftData
import SwiftUI

/// Pano: notlar durum sütunlarında; kart sürüklenerek durum değiştirilir.
struct BoardView: View {
    /// Kenar çubuğunda seçili kapsamın notları (defter, bölüm, etiket, filtre).
    let notes: [Note]
    var scopeTitle: String = ""
    var onOpen: (Note) -> Void = { _ in }

    @State private var dropTarget: NoteStatus?

    private var visibleNotes: [Note] { notes.filter { !$0.isTrashed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            GeometryReader { proxy in
                let width = max(230, (proxy.size.width - 2 * Metrics.Spacing.s4 - 3 * Metrics.Spacing.s3) / 4)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Metrics.Spacing.s3) {
                        ForEach(NoteStatus.allCases, id: \.self) { status in
                            column(status, notes: visibleNotes.filter { $0.status == status })
                                .frame(width: width, height: proxy.size.height - Metrics.Spacing.s4)
                        }
                    }
                    .padding(.horizontal, Metrics.Spacing.s4)
                }
            }
        }
        .background(Color.ds.surface)
    }

    private var header: some View {
        HStack(spacing: Metrics.Spacing.s3) {
            Text(scopeTitle.isEmpty ? String(localized: "Pano") : scopeTitle)
                .textStyle(.noteHeading)
                .foregroundStyle(Color.ds.ink)
            Text("\(visibleNotes.count) not")
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkTertiary)
            Spacer()
            Text("Kartları sürükleyerek durumu değiştirin")
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkTertiary)
        }
        .padding(.horizontal, Metrics.Spacing.s4)
        .padding(.vertical, Metrics.Spacing.s3)
    }

    private func column(_ status: NoteStatus, notes: [Note]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusBadge(status: status)
                Spacer()
                Text(notes.count, format: .number)
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Metrics.Spacing.s3)
            .padding(.vertical, Metrics.Spacing.s2 + 2)

            ScrollView {
                LazyVStack(spacing: Metrics.Spacing.s2) {
                    ForEach(notes) { note in
                        BoardCard(note: note)
                            .onTapGesture { onOpen(note) }
                            .draggable(DragPayload.note(note.id).string) {
                                BoardCard(note: note).frame(width: 220)
                            }
                    }
                    if notes.isEmpty {
                        Text("Not yok")
                            .textStyle(.caption)
                            .foregroundStyle(Color.ds.inkTertiary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .padding(.horizontal, Metrics.Spacing.s2)
                .padding(.bottom, Metrics.Spacing.s2)
            }
        }
        .background(Color.ds.windowBg, in: RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.lg, style: .continuous)
                .strokeBorder(dropTarget == status ? Color.ds.accent : Color.ds.separator.opacity(0.6), lineWidth: dropTarget == status ? 2 : 1)
        }
        .dropDestination(for: String.self) { items, _ in
            guard case .note(let id)? = items.lazy.compactMap(DragPayload.init(string:)).first,
                  let note = self.notes.first(where: { $0.id == id }) else { return false }
            withAnimation(.snappy) { note.setStatus(status) }
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? status : (dropTarget == status ? nil : dropTarget)
        }
    }
}

private struct BoardCard: View {
    let note: Note
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s1 + 2) {
            Text(note.title.isEmpty ? String(localized: "Başlıksız not") : note.title)
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
                .lineLimit(2)
            HStack(spacing: Metrics.Spacing.s2) {
                if let notebook = note.notebook {
                    GroupTag(name: notebook.name, color: notebook.color)
                }
                Spacer(minLength: 0)
                if let due = note.dueDate {
                    Label(due.formatted(.dateTime.day().month(.abbreviated)), systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                        .textStyle(.caption)
                        .foregroundStyle(note.isOverdue() ? Color.ds.statusBlocked : Color.ds.inkSecondary)
                }
            }
            if let progress = note.progress {
                ProgressBarView(value: progress, size: .sm, tint: note.status.color)
            }
        }
        .padding(Metrics.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ds.surface, in: RoundedRectangle(cornerRadius: Metrics.Radius.md + 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.md + 2, style: .continuous)
                .strokeBorder(isHovered ? Color.ds.accent.opacity(0.5) : Color.ds.separator, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Notu açmak için tıklayın; durumu değiştirmek için başka sütuna sürükleyin."))
    }
}
