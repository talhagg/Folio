import SwiftData
import SwiftUI

/// Kenar çubuğu: akıllı filtreler + DEFTERLER ağacı. Tasarım token'larıyla özel satırlar; ↑/↓ ile gezinilir.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    var now: Date = .now
    /// Her artışta yeni defter oluşturulur (⇧⌘N).
    var newNotebookRequest = 0

    @Environment(\.modelContext) private var context
    @Query(sort: \Notebook.sortIndex) private var notebooks: [Notebook]
    @Query private var notes: [Note]

    @State private var expanded: Set<UUID> = []
    @State private var didSetInitialExpansion = false
    @State private var renameTarget: LibraryItem?
    @State private var renameText = ""
    @State private var deleteTarget: LibraryItem?
    @State private var isHeaderHovered = false
    @State private var dropTarget: SidebarSelection?
    @State private var isEmptyTrashConfirmationShown = false

    private var trashCount: Int { notes.count(where: \.isTrashed) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SmartFilter.allCases, id: \.self) { filter in
                        row(
                            for: .smart(filter),
                            title: filter.title,
                            systemImage: filter.symbolName,
                            count: notes.count(where: { filter.includes($0, now: now) })
                        )
                    }

                    notebooksHeader
                        .padding(.top, Metrics.Spacing.s6 - 4)
                        .padding(.bottom, Metrics.Spacing.s1)

                    ForEach(notebooks) { notebook in
                        notebookRow(notebook)
                        if expanded.contains(notebook.id) {
                            ForEach(notebook.sortedSections) { section in
                                sectionRow(section)
                            }
                        }
                    }

                    trashRow
                        .padding(.top, Metrics.Spacing.s6 - 4)
                }
                .padding(.horizontal, Metrics.Spacing.s2 + 2)
                .padding(.vertical, Metrics.Spacing.s2)
            }
            .scrollIndicators(.never)
            .onChange(of: selection) { _, newValue in
                if let newValue { withAnimation { proxy.scrollTo(newValue) } }
            }
        }
        .background(Color.ds.sidebarBg)
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: moveSelection)
        .contextMenu {
            Button("Yeni Defter", action: addNotebook)
        }
        .onAppear(perform: expandInitially)
        .onChange(of: newNotebookRequest) { addNotebook() }
        .confirmationDialog(
            "Son Silinenler boşaltılsın mı?",
            isPresented: $isEmptyTrashConfirmationShown
        ) {
            Button("Boşalt", role: .destructive) { context.emptyTrash() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(trashCount) not kalıcı olarak silinecek. Bu işlem geri alınamaz.")
        }
        .alert(
            renameTarget?.renameTitle ?? "",
            isPresented: isPresented($renameTarget),
            presenting: renameTarget
        ) { target in
            TextField("Ad", text: $renameText)
            Button("Kaydet") { target.rename(to: renameText) }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog(
            deleteTarget?.deleteTitle ?? "",
            isPresented: isPresented($deleteTarget),
            presenting: deleteTarget
        ) { target in
            Button("Sil", role: .destructive) { delete(target) }
            Button("Vazgeç", role: .cancel) {}
        } message: { target in
            Text(target.deleteMessage)
        }
    }

    // MARK: - Satırlar

    private var notebooksHeader: some View {
        HStack {
            Text("Defterler")
                .textStyle(.sectionLabel)
                .foregroundStyle(Color.ds.inkTertiary)
            Spacer()
            Button(action: addNotebook) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ds.inkSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHeaderHovered ? 1 : 0)
            .help(Text("Yeni defter"))
            .accessibilityLabel(Text("Yeni defter"))
        }
        .padding(.horizontal, Metrics.Spacing.s2)
        .onHover { isHeaderHovered = $0 }
    }

    private func row(
        for item: SidebarSelection,
        title: String,
        systemImage: String,
        iconColor: Color = Color.ds.inkSecondary,
        count: Int,
        indent: CGFloat = 0,
        disclosure: Bool? = nil,
        onToggle: (() -> Void)? = nil,
        dragPayload: DragPayload? = nil
    ) -> some View {
        let isSelected = selection == item
        let isDropTarget = dropTarget == item
        return HStack(spacing: Metrics.Spacing.s2) {
            if let disclosure {
                Button {
                    onToggle?()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.ds.inkTertiary)
                        .rotationEffect(.degrees(disclosure ? 90 : 0))
                        .frame(width: 12, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(disclosure ? "Daralt" : "Genişlet"))
            }
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color.ds.ink)
                .lineLimit(1)
            Spacer(minLength: Metrics.Spacing.s2)
            Text(count, format: .number)
                .textStyle(.caption)
                .foregroundStyle(isSelected ? Color.ds.ink.opacity(0.7) : Color.ds.inkTertiary)
                .monospacedDigit()
        }
        .padding(.leading, Metrics.Spacing.s2 + indent)
        .padding(.trailing, Metrics.Spacing.s2 + 2)
        .frame(height: Metrics.Layout.rowHeight)
        .rowBackground(isSelected: isSelected)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Metrics.Radius.md, style: .continuous)
                    .fill(Color.ds.accentSoft.opacity(0.5))
                    .strokeBorder(Color.ds.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture { selection = item }
        .modifier(OptionalDraggable(payload: dragPayload))
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, on: item)
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTarget = item
            } else if dropTarget == item {
                dropTarget = nil
            }
        }
        .id(item)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func notebookRow(_ notebook: Notebook) -> some View {
        let isExpanded = expanded.contains(notebook.id)
        return row(
            for: .notebook(notebook.id),
            title: notebook.name,
            systemImage: isExpanded ? "folder" : "folder",
            iconColor: notebook.color.color,
            count: notebook.activeNotes.count,
            disclosure: isExpanded,
            onToggle: { toggle(notebook) },
            dragPayload: .notebook(notebook.id)
        )
        .contextMenu { notebookMenu(notebook) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { toggle(notebook) })
    }

    private func sectionRow(_ section: NoteSection) -> some View {
        row(
            for: .section(section.id),
            title: section.name,
            systemImage: "doc.text",
            count: section.activeNotes.count,
            indent: 20,
            dragPayload: .section(section.id)
        )
        .contextMenu { sectionMenu(section) }
    }

    private var trashRow: some View {
        row(
            for: .trash,
            title: String(localized: "Son Silinenler"),
            systemImage: "trash",
            count: trashCount
        )
        .contextMenu {
            Button("Son Silinenleri Boşalt…") { isEmptyTrashConfirmationShown = true }
                .disabled(trashCount == 0)
        }
        .help(Text("Silinen notlar \(Trash.retentionDays) gün sonra kalıcı olarak silinir."))
    }

    // MARK: - Sürükle-bırak

    /// Not → bölüme/deftere taşı ya da çöpe at; defter → sırala; bölüm → sırala ya da başka deftere taşı.
    private func handleDrop(_ items: [String], on target: SidebarSelection) -> Bool {
        guard let payload = items.lazy.compactMap(DragPayload.init(string:)).first else { return false }
        dropTarget = nil
        switch (payload, target) {
        case (.note(let id), .section(let sectionID)):
            guard let note = context.first(Note.self, id: id),
                  let section = context.first(NoteSection.self, id: sectionID) else { return false }
            withAnimation(.snappy) { context.moveNote(note, to: section) }
            return true
        case (.note(let id), .notebook(let notebookID)):
            guard let note = context.first(Note.self, id: id),
                  let notebook = context.first(Notebook.self, id: notebookID) else { return false }
            let section = context.sectionForNewNote(selection: .notebook(notebook.id))
            withAnimation(.snappy) { context.moveNote(note, to: section) }
            return true
        case (.note(let id), .trash):
            guard let note = context.first(Note.self, id: id) else { return false }
            withAnimation(.snappy) { context.moveToTrash(note) }
            return true
        case (.notebook(let id), .notebook(let targetID)):
            guard let notebook = context.first(Notebook.self, id: id) else { return false }
            withAnimation(.snappy) { context.moveNotebook(notebook, before: context.first(Notebook.self, id: targetID)) }
            return true
        case (.section(let id), .section(let targetID)):
            guard let section = context.first(NoteSection.self, id: id),
                  let target = context.first(NoteSection.self, id: targetID),
                  let notebook = target.notebook else { return false }
            withAnimation(.snappy) { context.moveSection(section, to: notebook, before: target) }
            return true
        case (.section(let id), .notebook(let notebookID)):
            guard let section = context.first(NoteSection.self, id: id),
                  let notebook = context.first(Notebook.self, id: notebookID) else { return false }
            withAnimation(.snappy) {
                context.moveSection(section, to: notebook, before: nil)
                expanded.insert(notebook.id)
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Menüler

    @ViewBuilder
    private func notebookMenu(_ notebook: Notebook) -> some View {
        Button("Yeni Bölüm") { addSection(to: notebook) }
        Button("Yeniden Adlandır…") { beginRename(.notebook(notebook)) }
        Menu("Renk") {
            ForEach(GroupColor.allCases, id: \.self) { color in
                Toggle(color.title, isOn: Binding(
                    get: { notebook.color == color },
                    set: { if $0 { notebook.color = color } }
                ))
            }
        }
        Divider()
        Button("Defteri Sil…", role: .destructive) { deleteTarget = .notebook(notebook) }
    }

    @ViewBuilder
    private func sectionMenu(_ section: NoteSection) -> some View {
        Button("Yeniden Adlandır…") { beginRename(.section(section)) }
        Divider()
        Button("Bölümü Sil…", role: .destructive) { deleteTarget = .section(section) }
    }

    // MARK: - Klavye

    private var visibleItems: [SidebarSelection] {
        var items = SmartFilter.allCases.map(SidebarSelection.smart)
        for notebook in notebooks {
            items.append(.notebook(notebook.id))
            if expanded.contains(notebook.id) {
                items += notebook.sortedSections.map { .section($0.id) }
            }
        }
        items.append(.trash)
        return items
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let index = selection.flatMap { items.firstIndex(of: $0) }
        switch direction {
        case .up:
            selection = items[max((index ?? 0) - 1, 0)]
        case .down:
            selection = items[min((index ?? -1) + 1, items.count - 1)]
        case .right:
            if case .notebook(let id) = selection { withAnimation(.snappy) { _ = expanded.insert(id) } }
        case .left:
            if case .notebook(let id) = selection { withAnimation(.snappy) { _ = expanded.remove(id) } }
        default:
            break
        }
    }

    // MARK: - Eylemler

    private func expandInitially() {
        guard !didSetInitialExpansion else { return }
        didSetInitialExpansion = true
        if let first = notebooks.first { expanded.insert(first.id) }
    }

    private func toggle(_ notebook: Notebook) {
        withAnimation(.snappy(duration: 0.2)) {
            if expanded.contains(notebook.id) {
                expanded.remove(notebook.id)
            } else {
                expanded.insert(notebook.id)
            }
        }
    }

    private func addNotebook() {
        let notebook = context.addNotebook(name: String(localized: "Yeni Defter"))
        let section = context.addSection(name: String(localized: "Genel"), to: notebook)
        expanded.insert(notebook.id)
        selection = .section(section.id)
        beginRename(.notebook(notebook))
    }

    private func addSection(to notebook: Notebook) {
        let section = context.addSection(name: String(localized: "Yeni Bölüm"), to: notebook)
        expanded.insert(notebook.id)
        selection = .section(section.id)
        beginRename(.section(section))
    }

    private func beginRename(_ target: LibraryItem) {
        renameText = target.currentName
        renameTarget = target
    }

    private func delete(_ target: LibraryItem) {
        switch target {
        case .notebook(let notebook):
            if selection == .notebook(notebook.id)
                || notebook.sortedSections.contains(where: { selection == .section($0.id) }) {
                selection = .smart(.all)
            }
            context.trashNotebook(notebook)
        case .section(let section):
            if selection == .section(section.id) {
                selection = section.notebook.map { .notebook($0.id) } ?? .smart(.all)
            }
            context.trashSection(section)
        }
    }

    private func isPresented(_ target: Binding<LibraryItem?>) -> Binding<Bool> {
        Binding { target.wrappedValue != nil } set: { if !$0 { target.wrappedValue = nil } }
    }
}

/// Yeniden adlandırma / silme hedefi.
private enum LibraryItem {
    case notebook(Notebook)
    case section(NoteSection)

    var currentName: String {
        switch self {
        case .notebook(let notebook): notebook.name
        case .section(let section): section.name
        }
    }

    var renameTitle: String {
        switch self {
        case .notebook: String(localized: "Defteri Yeniden Adlandır")
        case .section: String(localized: "Bölümü Yeniden Adlandır")
        }
    }

    var deleteTitle: String {
        switch self {
        case .notebook(let notebook): String(localized: "“\(notebook.name)” defteri silinsin mi?")
        case .section(let section): String(localized: "“\(section.name)” bölümü silinsin mi?")
        }
    }

    var deleteMessage: String {
        switch self {
        case .notebook(let notebook):
            String(localized: "İçindeki \(notebook.activeNotes.count) not Son Silinenler'e taşınacak; \(Trash.retentionDays) gün içinde geri yükleyebilirsiniz.")
        case .section(let section):
            String(localized: "İçindeki \(section.activeNotes.count) not Son Silinenler'e taşınacak; \(Trash.retentionDays) gün içinde geri yükleyebilirsiniz.")
        }
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch self {
        case .notebook(let notebook): notebook.name = trimmed
        case .section(let section): section.name = trimmed
        }
    }
}

/// `payload` varsa satırı sürüklenebilir yapar.
private struct OptionalDraggable: ViewModifier {
    let payload: DragPayload?

    func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload.string)
        } else {
            content
        }
    }
}

#if DEBUG
private struct SidebarPreview: View {
    @State private var selection: SidebarSelection? = .smart(.all)

    var body: some View {
        SidebarView(selection: $selection)
            .frame(width: Metrics.Layout.sidebarWidth, height: 560)
    }
}

#Preview("Light") {
    SidebarPreview()
        .modelContainer(SampleData.container())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SidebarPreview()
        .modelContainer(SampleData.container())
        .preferredColorScheme(.dark)
}
#endif
