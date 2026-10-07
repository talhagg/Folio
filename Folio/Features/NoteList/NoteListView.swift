import SwiftData
import SwiftUI

/// Not listesi sütunu: üstte tarih filtresi, altında tarih başlıklarıyla gruplu satırlar.
struct NoteListView: View {
    let filter: NoteFilter
    @Binding var dateFilter: DateFilter
    @Binding var selectedNoteID: UUID?
    var onClearSearch: (() -> Void)? = nil
    /// Silme isteği (onay ContentView'da).
    var onDelete: (Note) -> Void = { _ in }

    @Query private var fetchedNotes: [Note]
    @Query(sort: \Notebook.sortIndex) private var notebooks: [Notebook]
    /// Kaydırmayla silme düğmesi açık olan satır (aynı anda tek satır).
    @State private var revealedNoteID: UUID?
    @Environment(\.modelContext) private var context

    init(
        filter: NoteFilter,
        dateFilter: Binding<DateFilter>,
        selectedNoteID: Binding<UUID?>,
        onClearSearch: (() -> Void)? = nil,
        onDelete: @escaping (Note) -> Void = { _ in }
    ) {
        self.filter = filter
        self._dateFilter = dateFilter
        self._selectedNoteID = selectedNoteID
        self.onClearSearch = onClearSearch
        self.onDelete = onDelete
        self._fetchedNotes = Query(filter.descriptor)
    }

    private var notes: [Note] { filter.apply(to: fetchedNotes) }

    var body: some View {
        let notes = notes
        let groups = filter.isTrash
            ? (notes.isEmpty ? [] : [NoteGroup(group: .older, notes: notes.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) })])
            : DateGrouping.groups(for: notes, now: filter.now, calendar: filter.calendar)

        VStack(spacing: 0) {
            DateFilterBar(
                dateFilter: $dateFilter,
                resultCount: notes.count,
                searchText: filter.trimmedSearch,
                onClearSearch: onClearSearch
            )
                .padding(.horizontal, Metrics.Spacing.s3)
                .padding(.top, Metrics.Spacing.s3)
                .padding(.bottom, Metrics.Spacing.s3)

            Rectangle()
                .fill(Color.ds.separator)
                .frame(height: Metrics.Layout.separator)

            if notes.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if filter.isTrash {
                                trashHeader
                            }
                            ForEach(groups) { group in
                                if !filter.isTrash {
                                    Text(group.group.title)
                                    .textStyle(.sectionLabel)
                                    .foregroundStyle(Color.ds.inkTertiary)
                                    .padding(.horizontal, Metrics.Spacing.s3)
                                    .padding(.top, Metrics.Spacing.s4)
                                    .padding(.bottom, Metrics.Spacing.s1 + 2)
                                }
                                ForEach(group.notes) { note in
                                    row(note)
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.Spacing.s2)
                        .padding(.bottom, Metrics.Spacing.s4)
                    }
                    .onChange(of: selectedNoteID) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id) } }
                    }
                }
            }
        }
        .background(Color.ds.windowBg)
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            move(direction, in: groups.flatMap(\.notes))
        }
    }

    private var trashHeader: some View {
        HStack(alignment: .top, spacing: Metrics.Spacing.s2) {
            Image(systemName: "info.circle")
            Text("Notlar silindikten \(Trash.retentionDays) gün sonra kalıcı olarak silinir.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .textStyle(.caption)
        .foregroundStyle(Color.ds.inkSecondary)
        .padding(.horizontal, Metrics.Spacing.s3)
        .padding(.top, Metrics.Spacing.s3)
        .padding(.bottom, Metrics.Spacing.s1)
    }

    private func row(_ note: Note) -> some View {
        let isSelected = note.id == selectedNoteID
        return NoteRowView(
            note: note,
            now: filter.now,
            isSelected: isSelected,
            searchText: filter.trimmedSearch,
            onTogglePin: { togglePin(note) }
        )
            .rowBackground(isSelected: isSelected, cornerRadius: Metrics.Radius.lg)
            .modifier(SwipeToDelete(
                label: note.isTrashed ? String(localized: "Kalıcı Sil") : String(localized: "Sil"),
                isRevealed: revealedNoteID == note.id,
                onRevealChange: { revealed in
                    if revealed {
                        revealedNoteID = note.id
                    } else if revealedNoteID == note.id {
                        revealedNoteID = nil
                    }
                },
                onDelete: { onDelete(note) }
            ))
            .onTapGesture {
                revealedNoteID = nil
                selectedNoteID = note.id
            }
            .draggable(DragPayload.note(note.id).string) {
                Text(note.title.isEmpty ? String(localized: "Başlıksız not") : note.title)
                    .textStyle(.headline)
                    .padding(.horizontal, Metrics.Spacing.s3)
                    .padding(.vertical, Metrics.Spacing.s2)
                    .background(Color.ds.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.Radius.md))
            }
            .id(note.id)
            .contextMenu { menu(for: note) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func menu(for note: Note) -> some View {
        if note.isTrashed {
            Button("Geri Yükle") { withAnimation(.snappy) { context.restore(note) } }
            moveMenu(for: note, title: "Geri Yükle: Bölüm Seç")
            Divider()
            Button("Kalıcı Olarak Sil…", role: .destructive) { onDelete(note) }
        } else {
            Button(note.isPinned ? "Sabitlemeyi Kaldır" : "Sabitle") { togglePin(note) }
            moveMenu(for: note, title: "Taşı")
            Divider()
            Button("Son Silinenlere Taşı…", role: .destructive) { onDelete(note) }
        }
    }

    /// Sürüklemenin klavye/erişilebilirlik karşılığı: defter › bölüm listesi.
    private func moveMenu(for note: Note, title: LocalizedStringKey) -> some View {
        Menu(title) {
            ForEach(notebooks, id: \.id) { notebook in
                Section(notebook.name) {
                    ForEach(notebook.sortedSections, id: \.id) { section in
                        Button(section.name) {
                            withAnimation(.snappy) { context.moveNote(note, to: section) }
                        }
                        .disabled(section === note.section && !note.isTrashed)
                    }
                }
            }
        }
    }

    private func togglePin(_ note: Note) {
        withAnimation(.snappy) {
            note.isPinned.toggle()
            note.touch()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Metrics.Spacing.s2) {
            Image(systemName: filter.isTrash ? "trash" : filter.trimmedSearch.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.ds.inkTertiary)
            Text(filter.isTrash ? "Son Silinenler boş" : filter.trimmedSearch.isEmpty ? "Bu görünümde not yok" : "Sonuç bulunamadı")
                .textStyle(.headline)
                .foregroundStyle(Color.ds.ink)
            Text(emptyMessage)
                .textStyle(.callout)
                .foregroundStyle(Color.ds.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Metrics.Spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: LocalizedStringKey {
        if filter.isTrash { return "Silinen notlar \(Trash.retentionDays) gün burada kalır." }
        if dateFilter != .all { return "Tarih filtresini kaldırmayı deneyin." }
        if filter.isSearching { return "Başka bir kelimeyle aramayı deneyin." }
        return "Yeni bir not oluşturmak için ⌘N."
    }

    private func move(_ direction: MoveCommandDirection, in ordered: [Note]) {
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.id == selectedNoteID }
        switch direction {
        case .up: selectedNoteID = ordered[max((index ?? 0) - 1, 0)].id
        case .down: selectedNoteID = ordered[min((index ?? -1) + 1, ordered.count - 1)].id
        default: break
        }
    }
}

private struct NoteListPreview: View {
    @State private var dateFilter = DateFilter.all
    @State private var selected: UUID?

    var body: some View {
        NoteListView(
            filter: NoteFilter(selection: .smart(.all), dateFilter: dateFilter),
            dateFilter: $dateFilter,
            selectedNoteID: $selected
        )
        .frame(width: Metrics.Layout.listWidth, height: 640)
    }
}

#Preview("Light") {
    NoteListPreview()
        .modelContainer(SampleData.container())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    NoteListPreview()
        .modelContainer(SampleData.container())
        .preferredColorScheme(.dark)
}
