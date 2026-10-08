import SwiftData
import SwiftUI

/// Kenar çubuğu: akıllı filtreler + DEFTERLER ağacı. Tasarım token'larıyla özel satırlar; ↑/↓ ile gezinilir.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    /// Açık defterler (ana pencerede tutulur).
    @Binding var expanded: Set<UUID>
    var now: Date = .now
    /// Her artışta yeni defter oluşturulur (⇧⌘N).
    var newNotebookRequest = 0
    /// Bölümde yeni not açar (seçimi ContentView yönetir).
    var onNewNote: (NoteSection) -> Void = { _ in }
    var onImportFiles: () -> Void = {}
    var onImportURL: () -> Void = {}
    /// Notları JSON olarak dışa aktarır (defter/bölüm adı dosya adı olur).
    var onExport: ([Note], String) -> Void = { _, _ in }

    @Environment(\.modelContext) private var context
    @Query(sort: \Notebook.sortIndex) private var notebooks: [Notebook]
    @Query private var notes: [Note]

    @State private var didSetInitialExpansion = false
    @State private var namePrompt: NamePrompt?
    @State private var deleteTarget: LibraryItem?
    @State private var isHeaderHovered = false
    @State private var hoveredRow: SidebarSelection?
    @State private var dropTarget: SidebarSelection?
    @State private var isEmptyTrashConfirmationShown = false

    private var trashCount: Int { notes.count(where: \.isTrashed) }

    /// Etiketler ve not sayıları (çöptekiler hariç), alfabetik.
    private var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for note in notes where !note.isTrashed {
            for tag in note.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { ($0.key, $0.value) }
    }

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

                    sectionHeader("Görünümler")
                        .padding(.top, Metrics.Spacing.s6 - 4)
                        .padding(.bottom, Metrics.Spacing.s1)
                    row(for: .board, title: String(localized: "Pano"), systemImage: "rectangle.split.3x1",
                        count: notes.count(where: { !$0.isTrashed }))
                    row(for: .calendar, title: String(localized: "Takvim"), systemImage: "calendar",
                        count: notes.count(where: { !$0.isTrashed && ($0.dueDate != nil || $0.sortedTasks.contains { $0.dueDate != nil }) }))

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

                    let tags = tagCounts
                    if !tags.isEmpty {
                        sectionHeader("Etiketler")
                            .padding(.top, Metrics.Spacing.s6 - 4)
                            .padding(.bottom, Metrics.Spacing.s1)
                        ForEach(tags, id: \.tag) { item in
                            row(for: .tag(item.tag), title: item.tag, systemImage: "number", count: item.count)
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
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
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
        .sheet(item: $namePrompt) { prompt in
            nameSheet(prompt)
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

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .textStyle(.sectionLabel)
            .foregroundStyle(Color.ds.inkTertiary)
            .padding(.horizontal, Metrics.Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notebooksHeader: some View {
        HStack {
            Text("Defterler")
                .textStyle(.sectionLabel)
                .foregroundStyle(Color.ds.inkTertiary)
            Spacer()
            Button(action: addNotebook) {
                PlusIcon(size: 12, isHighlighted: isHeaderHovered)
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }
            .help(Text("Yeni defter (⇧⌘N)"))
            .accessibilityLabel(Text("Yeni defter"))
        }
        .padding(.leading, Metrics.Spacing.s2)
        .padding(.trailing, Metrics.Spacing.s1)
    }

    /// Her zaman görünen "Yeni Defter" düğmesi.
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.ds.separator)
                .frame(height: Metrics.Layout.separator)
            HStack(spacing: Metrics.Spacing.s1) {
                Button(action: addNotebook) {
                    HStack(spacing: Metrics.Spacing.s2) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.ds.accent)
                        Text("Yeni Defter")
                            .textStyle(.body)
                            .foregroundStyle(Color.ds.ink)
                        Spacer()
                    }
                    .padding(.horizontal, Metrics.Spacing.s2)
                    .frame(height: Metrics.Layout.rowHeight + 4)
                    .rowBackground(isSelected: false)
                }
                .buttonStyle(.plain)
                .help(Text("Yeni defter (⇧⌘N)"))

                Menu {
                    Button("Dosyadan İçe Aktar…", systemImage: "doc", action: onImportFiles)
                    Button("URL'den İçe Aktar…", systemImage: "link", action: onImportURL)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ds.inkSecondary)
                        .frame(width: 30, height: Metrics.Layout.rowHeight + 4)
                        .rowBackground(isSelected: false)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Text("İçe aktar: JSON, CSV, Excel, Word, Markdown, Confluence…"))
            }
            .padding(.horizontal, Metrics.Spacing.s2 + 2)
            .padding(.vertical, Metrics.Spacing.s2)
        }
        .background(Color.ds.sidebarBg)
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
        dragPayload: DragPayload? = nil,
        addAction: AddAction? = nil
    ) -> some View {
        let isSelected = selection == item
        let isDropTarget = dropTarget == item
        let showsAdd = addAction != nil && hoveredRow == item
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
            // Hover'da sayacın yerine + düğmesi.
            ZStack(alignment: .trailing) {
                Text(count, format: .number)
                    .textStyle(.caption)
                    .foregroundStyle(isSelected ? Color.ds.ink.opacity(0.7) : Color.ds.inkTertiary)
                    .monospacedDigit()
                    .opacity(showsAdd ? 0 : 1)
                if showsAdd, let addAction {
                    addButton(addAction)
                }
            }
        }
        .padding(.leading, Metrics.Spacing.s2 + indent)
        .padding(.trailing, Metrics.Spacing.s2 + 2)
        .frame(height: Metrics.Layout.rowHeight)
        .rowBackground(isSelected: isSelected)
        .onHover { hovering in
            if hovering {
                hoveredRow = item
            } else if hoveredRow == item {
                hoveredRow = nil
            }
        }
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
            dragPayload: .notebook(notebook.id),
            addAction: .notebook(notebook)
        )
        .accessibilityAction(named: Text("Yeni Not")) { newNote(in: notebook) }
        .accessibilityAction(named: Text("Yeni Bölüm")) { addSection(to: notebook) }
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
            dragPayload: .section(section.id),
            addAction: .section(section)
        )
        .accessibilityAction(named: Text("Yeni Not")) { onNewNote(section) }
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

    // MARK: - Hızlı ekleme

    private enum AddAction {
        case notebook(Notebook)
        case section(NoteSection)
    }

    /// Defterde: Yeni Not / Yeni Bölüm menüsü. Bölümde: doğrudan yeni not.
    @ViewBuilder
    private func addButton(_ action: AddAction) -> some View {
        switch action {
        case .notebook(let notebook):
            Menu {
                Button("Yeni Not", systemImage: "square.and.pencil") { newNote(in: notebook) }
                Button("Yeni Bölüm", systemImage: "doc.badge.plus") { addSection(to: notebook) }
            } label: {
                PlusIcon(size: 11, isHighlighted: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Text("\(notebook.name) defterine ekle"))
        case .section(let section):
            Button { onNewNote(section) } label: {
                PlusIcon(size: 11, isHighlighted: true)
            }
            .buttonStyle(.plain)
            .help(Text("\(section.name) bölümüne yeni not"))
        }
    }

    private func newNote(in notebook: Notebook) {
        let section = context.sectionForNewNote(selection: .notebook(notebook.id))
        expanded.insert(notebook.id)
        onNewNote(section)
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
        Button("Defteri Dışa Aktar (JSON)…") { onExport(notebook.activeNotes, notebook.name) }
            .disabled(notebook.activeNotes.isEmpty)
        Divider()
        Button("Defteri Sil…", role: .destructive) { deleteTarget = .notebook(notebook) }
    }

    @ViewBuilder
    private func sectionMenu(_ section: NoteSection) -> some View {
        Button("Yeniden Adlandır…") { beginRename(.section(section)) }
        Button("Bölümü Dışa Aktar (JSON)…") { onExport(section.activeNotes, section.name) }
            .disabled(section.activeNotes.isEmpty)
        Divider()
        Button("Bölümü Sil…", role: .destructive) { deleteTarget = .section(section) }
    }

    // MARK: - Klavye

    private var visibleItems: [SidebarSelection] {
        var items = SmartFilter.allCases.map(SidebarSelection.smart) + [.board, .calendar]
        for notebook in notebooks {
            items.append(.notebook(notebook.id))
            if expanded.contains(notebook.id) {
                items += notebook.sortedSections.map { .section($0.id) }
            }
        }
        items += tagCounts.map { .tag($0.tag) }
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

    /// Önce ad sorulur; defter yalnızca onaylanınca oluşur.
    private func addNotebook() {
        namePrompt = .newNotebook
    }

    private func addSection(to notebook: Notebook) {
        namePrompt = .newSection(notebook)
    }

    private func beginRename(_ target: LibraryItem) {
        namePrompt = .rename(target)
    }

    @ViewBuilder
    private func nameSheet(_ prompt: NamePrompt) -> some View {
        switch prompt {
        case .newNotebook:
            let names = notebooks.map(\.name)
            let palette = GroupColor.allCases
            NameSheet(
                kind: .notebook,
                title: String(localized: "Yeni Defter"),
                confirmTitle: String(localized: "Oluştur"),
                initialName: NameValidation.uniqueName(String(localized: "Yeni Defter"), existing: names),
                existingNames: names,
                initialColor: palette[notebooks.count % palette.count]
            ) { name, color in
                let notebook = context.addNotebook(name: name, color: color)
                let section = context.addSection(name: String(localized: "Genel"), to: notebook)
                expanded.insert(notebook.id)
                selection = .section(section.id)
            }
        case .newSection(let notebook):
            let names = (notebook.sections ?? []).map(\.name)
            NameSheet(
                kind: .section,
                title: String(localized: "\(notebook.name) defterine yeni bölüm"),
                confirmTitle: String(localized: "Oluştur"),
                initialName: NameValidation.uniqueName(String(localized: "Yeni Bölüm"), existing: names),
                existingNames: names
            ) { name, _ in
                let section = context.addSection(name: name, to: notebook)
                expanded.insert(notebook.id)
                selection = .section(section.id)
            }
        case .rename(let target):
            NameSheet(
                kind: target.color == nil ? .section : .notebook,
                title: target.renameTitle,
                confirmTitle: String(localized: "Kaydet"),
                initialName: target.currentName,
                existingNames: target.siblingNames,
                initialColor: target.color
            ) { name, color in
                target.rename(to: name)
                if case .notebook(let notebook) = target, let color { notebook.color = color }
            }
        }
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

private enum NamePrompt: Identifiable {
    case newNotebook
    case newSection(Notebook)
    case rename(LibraryItem)

    var id: String {
        switch self {
        case .newNotebook: "notebook"
        case .newSection(let notebook): "section-\(notebook.id)"
        case .rename(let item): "rename-\(item.id)"
        }
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

    var id: UUID {
        switch self {
        case .notebook(let notebook): notebook.id
        case .section(let section): section.id
        }
    }

    var color: GroupColor? {
        if case .notebook(let notebook) = self { return notebook.color }
        return nil
    }

    /// Aynı düzeydeki diğer adlar (kendisi hariç).
    var siblingNames: [String] {
        switch self {
        case .notebook(let notebook):
            let all = (try? notebook.modelContext?.fetch(FetchDescriptor<Notebook>())) ?? []
            return all.filter { $0.id != notebook.id }.map(\.name)
        case .section(let section):
            return (section.notebook?.sections ?? []).filter { $0.id != section.id }.map(\.name)
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

/// Kenar çubuğundaki + simgesi: 22 pt tıklama alanı, hover'da zemin.
private struct PlusIcon: View {
    var size: CGFloat
    var isHighlighted: Bool

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isHighlighted ? Color.ds.ink : Color.ds.inkSecondary)
            .frame(width: 22, height: 22)
            .background(
                Color.ds.surfaceHover.opacity(isHighlighted ? 1 : 0),
                in: RoundedRectangle(cornerRadius: Metrics.Radius.sm + 1, style: .continuous)
            )
            .contentShape(Rectangle())
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
    @State private var expanded: Set<UUID> = []

    var body: some View {
        SidebarView(selection: $selection, expanded: $expanded)
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
