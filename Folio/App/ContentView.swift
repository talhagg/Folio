import CoreSpotlight
import SwiftData
import SwiftUI

/// 3 sütunlu ana pencere: kenar çubuğu → not listesi → editör.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \Notebook.sortIndex) private var notebooks: [Notebook]

    @State private var selection: SidebarSelection?
    @State private var selectedNoteID: UUID?
    @State private var dateFilter: DateFilter = .all
    @State private var searchText: String
    @State private var deleteRequest: Note?
    @State private var newNotebookRequest = 0
    @State private var isFileImporterShown = false
    @State private var isURLImportShown = false
    @State private var importMessage: String?
    @State private var exportRequest: ExportRequest?

    private struct ExportRequest {
        var document: ExportDocument
        var format: ExportFormat
        var fileName: String
    }
    @State private var viewMode: ViewMode
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isPaletteShown: Bool
    @AppStorage(ListDensity.storageKey) private var densityRaw = ListDensity.detailed.rawValue
    @Environment(\.openSettings) private var openSettings

    /// Odak modu: yalnızca editör (kenar çubuğu ve liste gizli).
    private var isFocusMode: Bool { columnVisibility == .detailOnly }

    /// Kenar çubuğunda açık defterler; pano/liste düzeni değişince kaybolmasın diye burada.
    @State private var expandedNotebooks: Set<UUID> = []
    @FocusState private var isSearchFocused: Bool

    private let sidebarWidth = WindowLayout.storedWidth(
        WindowLayout.sidebarWidthKey,
        default: Metrics.Layout.sidebarWidth,
        range: Metrics.Layout.sidebarMinWidth...Metrics.Layout.sidebarMaxWidth
    )
    private let listWidth = WindowLayout.storedWidth(
        WindowLayout.listWidthKey,
        default: Metrics.Layout.listWidth,
        range: 260...420
    )

    init(
        selection: SidebarSelection = .smart(.all),
        searchText: String = "",
        viewMode: ViewMode = .list,
        showsPalette: Bool = false
    ) {
        self._viewMode = State(initialValue: viewMode)
        self._isPaletteShown = State(initialValue: showsPalette)
        self._selection = State(initialValue: selection)
        self._searchText = State(initialValue: searchText)
    }

    private var filter: NoteFilter {
        NoteFilter(selection: selection, dateFilter: dateFilter, searchText: searchText, now: .now)
    }

    /// Pano ve takvim için seçili kapsamın notları (tarih filtresi ve arama dahil).
    private var scopeNotes: [Note] { filter.apply(to: allNotes) }

    /// Başlıktaki sayaç: tarih filtresinden bağımsız, yalnızca kenar çubuğu seçimi.
    private var selectionNotes: [Note] {
        let now = Date.now
        guard let selection else { return allNotes.filter { !$0.isTrashed } }
        return allNotes.filter { selection.includes($0, now: now) }
    }

    private var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return allNotes.first { $0.id == selectedNoteID }
    }

    var body: some View {
        // Pano tüm genişliği kullanır: iki sütun (kenar çubuğu + pano); diğer görünümler üç sütun.
        Group {
            if viewMode == .board {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } detail: {
                    BoardView(notes: scopeNotes, scopeTitle: title, onOpen: { note in
                        viewMode = .list
                        show(note)
                    })
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } content: {
                    contentColumn
                } detail: {
                    detail
                }
            }
        }
        .overlay(alignment: .top) { paletteOverlay }
        .overlay(alignment: .topTrailing) { focusExitButton }
        .toolbar(isFocusMode ? .hidden : .automatic, for: .windowToolbar)
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        // Toolbar tek yerde ve sabit: içerik değişince öğeler kaybolup kaymasın, kullanılamayanlar soluklaşsın.
        // Sade toolbar: görünüm geçişi, arama, "⋯" (dışa/içe aktar, tema), Yeni Not.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Görünüm", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help(Text("Liste, Pano ya da Takvim (⌃⌘1–3)"))

                ToolbarSearchField(text: $searchText, isFocused: $isSearchFocused)

                moreMenu

                // Bölünmüş düğme: tıklama boş not, ok şablon menüsü.
                Menu {
                    Button("Boş Not") { addNote() }
                    Divider()
                    ForEach(NoteTemplate.allCases) { template in
                        Button { addNote(template: template) } label: {
                            Label(template.title, systemImage: template.symbolName)
                        }
                    }
                } label: {
                    Label("Yeni Not", systemImage: "square.and.pencil")
                        .labelStyle(.titleAndIcon)
                } primaryAction: {
                    addNote()
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .tint(Color.ds.accent)
                .help(Text("Yeni not (⌘N) — ok: şablondan"))
            }
        }
        .focusedSceneValue(\.noteActions, commandActions)
        // Uygulama içi bağlantılar: not, etiket, [[başlık]] — önizleme, editör, bildirim ve Spotlight'tan.
        .environment(\.openURL, OpenURLAction { url in
            guard let link = AppLink(url: url) else { return .systemAction }
            AppNavigator.shared.open(link)
            return .handled
        })
        .onAppear { QuickActions.shared.openWindow = openWindow }
        // Spotlight sonucundan açılış.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = SpotlightIndexer.noteID(from: activity) { AppNavigator.shared.open(.note(id)) }
        }
        .onOpenURL { url in
            if let link = AppLink(url: url) { AppNavigator.shared.open(link) }
        }
        .onChange(of: AppNavigator.shared.request) { _, request in
            guard let request else { return }
            AppNavigator.shared.request = nil
            navigate(to: request)
        }
        .fileImporter(
            isPresented: $isFileImporterShown,
            allowedContentTypes: FileImporter.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): importMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isURLImportShown) {
            URLImportView { section, count in
                showImported(section)
                importMessage = String(localized: "\(count) not \"\(ModelContext.importNotebookName)\" defterine eklendi.")
            }
        }
        .alert(
            "Folio",
            isPresented: Binding { importMessage != nil } set: { if !$0 { importMessage = nil } }
        ) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .persistWindowFrame()
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding { deleteRequest != nil } set: { if !$0 { deleteRequest = nil } },
            presenting: deleteRequest
        ) { note in
            if note.isTrashed {
                Button("Kalıcı Olarak Sil", role: .destructive) { context.deletePermanently(note) }
            } else {
                Button("Son Silinenlere Taşı", role: .destructive) {
                    withAnimation(.snappy) { context.moveToTrash(note) }
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { note in
            Text(note.isTrashed
                 ? "Bu işlem geri alınamaz."
                 : "Not \(Trash.retentionDays) gün boyunca Son Silinenler'de kalır, sonra kalıcı olarak silinir.")
        }
        .task {
            context.purgeExpiredTrash()
            selectFirstIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { context.purgeExpiredTrash() }
        }
        .onChange(of: filter.selection) { clearHiddenSelection() }
        .onChange(of: dateFilter) { clearHiddenSelection() }
        .onChange(of: filter.trimmedSearch) {
            // Aramada ilk sonuç seçilsin; arama bitince seçim korunur.
            if filter.isSearching {
                selectedNoteID = nil
            }
            clearHiddenSelection()
        }
        // Seçili not çöpe atılır, taşınır ya da silinirse bir sonrakine geç.
        .onChange(of: selectedNote.map { filter.matches($0) } ?? false) { clearHiddenSelection() }
    }

    private var sidebar: some View {
        SidebarView(
            selection: $selection,
            expanded: $expandedNotebooks,
            newNotebookRequest: newNotebookRequest,
            onNewNote: { addNote(in: $0) },
            onImportFiles: { isFileImporterShown = true },
            onImportURL: { isURLImportShown = true },
            onExport: { notes, name in export(notes, as: .json, fallbackName: name) }
        )
        .persistWidth(key: WindowLayout.sidebarWidthKey)
        // fileImporter ile aynı görünümde olursa biri çalışmıyor; dışa aktarma kenar çubuğunda (her düzende var).
        .fileExporter(
            isPresented: Binding { exportRequest != nil } set: { if !$0 { exportRequest = nil } },
            document: exportRequest?.document,
            contentType: exportRequest?.format.contentType ?? .data,
            defaultFilename: exportRequest?.fileName
        ) { result in
            if case .failure(let error) = result {
                importMessage = error.localizedDescription
            }
            exportRequest = nil
        }
        .navigationSplitViewColumnWidth(
            min: Metrics.Layout.sidebarMinWidth,
            ideal: sidebarWidth,
            max: Metrics.Layout.sidebarMaxWidth
        )
    }

    private var contentColumn: some View {
        Group {
            if viewMode == .calendar {
                CalendarView(notes: scopeNotes, selectedNoteID: $selectedNoteID)
            } else {
                noteList
            }
        }
        .persistWidth(key: WindowLayout.listWidthKey)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            importFiles(files)
            return true
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: listWidth, max: 420)
    }

    /// "⋯" menüsü: dışa/içe aktarma, tema ve ayarlar.
    private var moreMenu: some View {
        Menu {
            Menu("Dışa Aktar") {
                ForEach(ExportFormat.allCases) { format in
                    Button("\(format.title)…") {
                        if let selectedNote { export([selectedNote], as: format) }
                    }
                    .disabled(selectedNote == nil)
                }
                Divider()
                Button("Tüm Notlar (JSON)…") {
                    export(allNotes.filter { !$0.isTrashed }, as: .json, fallbackName: String(localized: "Folio Yedek"))
                }
            }
            Menu("İçe Aktar") {
                Button("Dosyadan…") { isFileImporterShown = true }
                Button("URL'den…") { isURLImportShown = true }
            }
            Divider()
            Picker("Not Listesi", selection: $densityRaw) {
                ForEach(ListDensity.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Tema", selection: Bindable(ThemeStore.shared).appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Vurgu Rengi", selection: Bindable(ThemeStore.shared).accent) {
                ForEach(AccentTheme.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            SettingsLink { Text("Ayarlar…") }
        } label: {
            Label("Daha Fazla", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help(Text("Dışa aktar, içe aktar, tema"))
    }

    // MARK: - Odak modu ve komut paleti

    private func toggleFocusMode() {
        withAnimation(.snappy) {
            if isFocusMode {
                columnVisibility = .all
            } else {
                // Pano/takvimde odak, seçili notun editöründe olur.
                if viewMode != .list { viewMode = .list }
                columnVisibility = .detailOnly
            }
        }
    }

    @ViewBuilder
    private var focusExitButton: some View {
        if isFocusMode && !isPaletteShown {
            Button { toggleFocusMode() } label: {
                Label("Odak modundan çık", systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ds.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.ds.surfaceHover, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(Text("Odak modundan çık (Esc ya da ⌘.)"))
            .padding(Metrics.Spacing.s3)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var paletteOverlay: some View {
        if isPaletteShown {
            ZStack(alignment: .top) {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isPaletteShown = false }
                CommandPaletteView(
                    items: paletteItems,
                    suggestions: paletteSuggestions,
                    onDismiss: { isPaletteShown = false }
                )
                .padding(.top, 72)
            }
            .transition(.opacity)
        }
    }

    /// Sorgu boşken: son düzenlenen 5 not, sonra komutlar.
    private var paletteSuggestions: [PaletteItem] {
        Array(paletteNoteItems.prefix(5)) + paletteCommands
    }

    private var paletteItems: [PaletteItem] {
        paletteCommands + paletteNoteItems + paletteLocationItems
    }

    private var paletteNoteItems: [PaletteItem] {
        allNotes.filter { !$0.isTrashed }.map { note in
            PaletteItem(
                id: "note-\(note.id)",
                kind: .note,
                title: note.title.isEmpty ? String(localized: "Başlıksız not") : note.title,
                subtitle: note.locationPath ?? "",
                symbolName: "doc.text",
                perform: {
                    if viewMode != .list { viewMode = .list }
                    show(note)
                }
            )
        }
    }

    private var paletteLocationItems: [PaletteItem] {
        var items: [PaletteItem] = []
        for notebook in notebooks {
            items.append(PaletteItem(
                id: "notebook-\(notebook.id)", kind: .notebook, title: notebook.name,
                subtitle: String(localized: "Defter"), symbolName: "book.closed",
                perform: { goTo(.notebook(notebook.id)) }
            ))
            for section in notebook.sortedSections {
                items.append(PaletteItem(
                    id: "section-\(section.id)", kind: .section, title: section.name,
                    subtitle: notebook.name, symbolName: "folder",
                    perform: { goTo(.section(section.id)) }
                ))
            }
        }
        var tags = Set<String>()
        for note in allNotes where !note.isTrashed { tags.formUnion(note.tags) }
        for tag in tags.sorted() {
            items.append(PaletteItem(
                id: "tag-\(tag)", kind: .tag, title: "#" + tag,
                subtitle: String(localized: "Etiket"), symbolName: "number",
                perform: { goTo(.tag(tag)) }
            ))
        }
        return items
    }

    private func goTo(_ newSelection: SidebarSelection) {
        searchText = ""
        dateFilter = .all
        selectedNoteID = nil
        selection = newSelection
    }

    private var paletteCommands: [PaletteItem] {
        var items: [PaletteItem] = [
            PaletteItem(id: "cmd-new", kind: .command, title: String(localized: "Yeni Not"),
                        symbolName: "square.and.pencil", keywords: "oluştur ekle", shortcut: "⌘N",
                        perform: { addNote() }),
            PaletteItem(id: "cmd-notebook", kind: .command, title: String(localized: "Yeni Defter"),
                        symbolName: "book.closed", keywords: "oluştur ekle", shortcut: "⇧⌘N",
                        perform: { newNotebookRequest += 1 }),
            PaletteItem(id: "cmd-sticky", kind: .command, title: String(localized: "Yeni Yapışkan Not"),
                        symbolName: "note.text", keywords: "sticky", shortcut: "⌥⌘N",
                        perform: { newSticky() }),
        ]
        for template in NoteTemplate.allCases {
            items.append(PaletteItem(
                id: "cmd-template-\(template.id)", kind: .command,
                title: String(localized: "Şablondan Yeni Not: \(template.title)"),
                symbolName: template.symbolName, keywords: "şablon",
                perform: { addNote(template: template) }
            ))
        }
        for (index, mode) in ViewMode.allCases.enumerated() {
            items.append(PaletteItem(
                id: "cmd-view-\(mode.rawValue)", kind: .command,
                title: String(localized: "Görünüm: \(mode.title)"),
                symbolName: mode.symbolName, keywords: "görünüm", shortcut: "⌃⌘\(index + 1)",
                perform: { withAnimation(.snappy) { viewMode = mode } }
            ))
        }
        items.append(PaletteItem(
            id: "cmd-focus", kind: .command,
            title: isFocusMode ? String(localized: "Odak Modundan Çık") : String(localized: "Odak Modu"),
            symbolName: "arrow.up.left.and.arrow.down.right", keywords: "tam ekran yalnız editör", shortcut: "⌘.",
            perform: { toggleFocusMode() }
        ))
        items.append(PaletteItem(
            id: "cmd-search", kind: .command, title: String(localized: "Notlarda Ara"),
            symbolName: "magnifyingglass", keywords: "bul", shortcut: "⌘F",
            perform: { isSearchFocused = true }
        ))
        for (index, smart) in SmartFilter.allCases.enumerated() {
            items.append(PaletteItem(
                id: "cmd-smart-\(index)", kind: .command, title: smart.title,
                subtitle: String(localized: "Filtre"), symbolName: smart.symbolName, shortcut: "⌘\(index + 1)",
                perform: { goTo(.smart(smart)) }
            ))
        }
        items.append(PaletteItem(
            id: "cmd-trash", kind: .command, title: String(localized: "Son Silinenler"),
            symbolName: "trash", keywords: "çöp",
            perform: { goTo(.trash) }
        ))
        if let note = selectedNote {
            for format in ExportFormat.allCases {
                items.append(PaletteItem(
                    id: "cmd-export-\(format.id)", kind: .command,
                    title: String(localized: "Notu Dışa Aktar: \(format.title)"),
                    symbolName: "square.and.arrow.up", keywords: "export kaydet",
                    perform: { export([note], as: format) }
                ))
            }
            if !note.isTrashed {
                items.append(PaletteItem(
                    id: "cmd-pin", kind: .command,
                    title: note.isPinned ? String(localized: "Sabitlemeyi Kaldır") : String(localized: "Sabitle"),
                    symbolName: "pin", shortcut: "⌘P",
                    perform: { withAnimation(.snappy) { note.isPinned.toggle(); note.touch() } }
                ))
                items.append(PaletteItem(
                    id: "cmd-open-sticky", kind: .command, title: String(localized: "Yapışkan Not Olarak Aç"),
                    symbolName: "note.text", shortcut: "⌥⌘S",
                    perform: { openWindow(id: StickyNote.windowID, value: note.id) }
                ))
            }
        }
        items += [
            PaletteItem(id: "cmd-export-all", kind: .command, title: String(localized: "Tüm Notları Dışa Aktar (JSON)"),
                        symbolName: "square.and.arrow.up.on.square", keywords: "yedek export",
                        perform: { export(allNotes.filter { !$0.isTrashed }, as: .json, fallbackName: String(localized: "Folio Yedek")) }),
            PaletteItem(id: "cmd-import-file", kind: .command, title: String(localized: "Dosyadan İçe Aktar"),
                        symbolName: "square.and.arrow.down", keywords: "import csv json excel word", shortcut: "⇧⌘I",
                        perform: { isFileImporterShown = true }),
            PaletteItem(id: "cmd-import-url", kind: .command, title: String(localized: "URL'den İçe Aktar"),
                        symbolName: "link", keywords: "import web confluence", shortcut: "⇧⌘U",
                        perform: { isURLImportShown = true }),
        ]
        for mode in AppearanceMode.allCases {
            items.append(PaletteItem(
                id: "cmd-appearance-\(mode.id)", kind: .command, title: String(localized: "Tema: \(mode.title)"),
                symbolName: "circle.lefthalf.filled", keywords: "görünüm açık koyu",
                perform: { ThemeStore.shared.appearance = mode }
            ))
        }
        for accent in AccentTheme.allCases {
            items.append(PaletteItem(
                id: "cmd-accent-\(accent.id)", kind: .command, title: String(localized: "Vurgu Rengi: \(accent.title)"),
                symbolName: "paintpalette", keywords: "tema renk",
                perform: { ThemeStore.shared.accent = accent }
            ))
        }
        for density in ListDensity.allCases {
            items.append(PaletteItem(
                id: "cmd-density-\(density.rawValue)", kind: .command,
                title: String(localized: "Not Listesi: \(density.title)"),
                symbolName: "list.dash", keywords: "yoğunluk",
                perform: { densityRaw = density.rawValue }
            ))
        }
        items.append(PaletteItem(
            id: "cmd-settings", kind: .command, title: String(localized: "Ayarlar"),
            symbolName: "gearshape", keywords: "tercihler", shortcut: "⌘,",
            perform: { openSettings() }
        ))
        return items
    }

    private var noteList: some View {
        NoteListView(
            filter: filter,
            dateFilter: $dateFilter,
            selectedNoteID: $selectedNoteID,
            onClearSearch: { searchText = "" },
            onDelete: { deleteRequest = $0 },
            onOpenSticky: { openWindow(id: StickyNote.windowID, value: $0.id) },
            onExport: { note, format in export([note], as: format) }
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedNote {
            NoteEditorView(
                note: selectedNote,
                onDeletePermanently: { deleteRequest = selectedNote }
            )
                // Not değişince editör sıfırlansın; yoksa alanların onChange'i yeni notu "düzenlenmiş" sayar.
                .id(selectedNote.id)
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: Metrics.Spacing.s2) {
            Image(systemName: selection == .trash ? "trash" : "text.page")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Color.ds.inkTertiary)
            Text(selection == .trash ? "Silinen not seçilmedi" : "Bir not seçin")
                .textStyle(.headline)
                .foregroundStyle(Color.ds.inkSecondary)
            if selection != .trash {
                Text("ya da ⌘N ile yenisini oluşturun")
                    .textStyle(.callout)
                    .foregroundStyle(Color.ds.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ds.surface)
    }

    // MARK: - Başlık

    private var title: String {
        if filter.isSearching { return String(localized: "Arama") }
        switch selection {
        case .smart(let filter):
            return filter.title
        case .notebook(let id):
            return notebooks.first { $0.id == id }?.name ?? "Folio"
        case .section(let id):
            return section(id)?.name ?? "Folio"
        case .trash:
            return String(localized: "Son Silinenler")
        case .tag(let tag):
            return "#" + tag
        case nil:
            return "Folio"
        }
    }

    private var subtitle: String {
        if filter.isSearching {
            return filter.isTrash
                ? String(localized: "“\(filter.trimmedSearch)” · Son Silinenler'de")
                : String(localized: "“\(filter.trimmedSearch)” · tüm notlarda")
        }
        let count = String(localized: "\(selectionNotes.count) not")
        if case .section(let id) = selection, let notebook = section(id)?.notebook {
            return "\(notebook.name) · \(count)"
        }
        return count
    }

    private var deleteTitle: String {
        guard let deleteRequest else { return "" }
        let name = deleteRequest.title.isEmpty ? String(localized: "Başlıksız not") : deleteRequest.title
        return deleteRequest.isTrashed
            ? String(localized: "“\(name)” kalıcı olarak silinsin mi?")
            : String(localized: "“\(name)” Son Silinenler'e taşınsın mı?")
    }

    private func section(_ id: UUID) -> NoteSection? {
        notebooks.lazy.flatMap { $0.sections ?? [] }.first { $0.id == id }
    }

    // MARK: - Komutlar

    private var commandActions: NoteCommandActions {
        let note = selectedNote
        var deleteNote: (@MainActor () -> Void)?
        var togglePin: (@MainActor () -> Void)?
        if let note {
            deleteNote = { deleteRequest = note }
            if !note.isTrashed {
                togglePin = {
                    withAnimation(.snappy) {
                        note.isPinned.toggle()
                        note.touch()
                    }
                }
            }
        }
        var exportNote: (@MainActor (ExportFormat) -> Void)?
        if let note {
            exportNote = { format in export([note], as: format) }
        }
        var openSticky: (@MainActor () -> Void)?
        if let note, !note.isTrashed {
            openSticky = { openWindow(id: StickyNote.windowID, value: note.id) }
        }
        let exportAll: @MainActor () -> Void = {
            export(allNotes.filter { !$0.isTrashed }, as: .json, fallbackName: String(localized: "Folio Yedek"))
        }
        return NoteCommandActions(
            newNote: { addNote() },
            newNotebook: { newNotebookRequest += 1 },
            deleteNote: deleteNote,
            togglePin: togglePin,
            isPinned: note?.isPinned ?? false,
            isTrash: note?.isTrashed ?? false,
            selectSmartFilter: { filter in
                searchText = ""
                selection = .smart(filter)
            },
            focusSearch: { isSearchFocused = true },
            importFiles: { isFileImporterShown = true },
            importURL: { isURLImportShown = true },
            exportNote: exportNote,
            exportAll: exportAll,
            openSticky: openSticky,
            newSticky: { newSticky() },
            newFromTemplate: { addNote(template: $0) },
            viewMode: viewMode,
            setViewMode: { mode in withAnimation(.snappy) { viewMode = mode } },
            isFocusMode: isFocusMode,
            toggleFocusMode: { toggleFocusMode() },
            showCommandPalette: { isPaletteShown = true }
        )
    }

    // MARK: - Eylemler

    private func export(_ notes: [Note], as format: ExportFormat, fallbackName: String = String(localized: "Notlar")) {
        guard !notes.isEmpty else { return }
        do {
            let data = try NoteExporter.data(for: notes, format: format)
            exportRequest = ExportRequest(
                document: ExportDocument(data: data),
                format: format,
                fileName: NoteExporter.suggestedFileName(for: notes, fallback: fallbackName)
            )
        } catch {
            importMessage = String(localized: "Dışa aktarılamadı: \(error.localizedDescription)")
        }
    }

    private func navigate(to link: AppLink) {
        NSApp.activate()
        switch link {
        case .note(let id):
            guard let note = allNotes.first(where: { $0.id == id }) else { return }
            show(note)
        case .noteTitle(let title):
            let key = NoteLinkSyntax.normalizedTag(title)
            if let note = allNotes.first(where: { !$0.isTrashed && NoteLinkSyntax.normalizedTag($0.title) == key }) {
                show(note)
            } else {
                // Bağlanan not yoksa oluştur (seçili bölümde).
                let section = context.sectionForNewNote(selection: selection == .trash ? nil : selection)
                let note = context.addNote(in: section, title: title)
                show(note)
            }
        case .tag(let tag):
            searchText = ""
            dateFilter = .all
            selectedNoteID = nil
            selection = .tag(NoteLinkSyntax.normalizedTag(tag))
        }
    }

    /// Notu görünür kılıp seçer: görünüm notu kapsamıyorsa notun bölümüne geçer.
    private func show(_ note: Note) {
        searchText = ""
        dateFilter = .all
        if note.isTrashed {
            selection = .trash
        } else if !(selection?.includes(note, now: .now) ?? false) {
            selection = note.section.map { .section($0.id) } ?? .smart(.all)
        }
        selectedNoteID = note.id
    }

    /// Seçili bölümde boş bir not oluşturup yapışkan pencerede açar.
    private func newSticky() {
        let section = context.sectionForNewNote(selection: selection == .trash ? nil : selection)
        let note = context.addNote(in: section)
        openWindow(id: StickyNote.windowID, value: note.id)
    }

    private func importFiles(_ urls: [URL]) {
        let summary = FileImportRunner.run(urls, in: context)
        if let section = summary.lastSection { showImported(section) }
        importMessage = summary.message.isEmpty ? ImportError.empty.localizedDescription : summary.message
    }

    private func showImported(_ section: NoteSection) {
        searchText = ""
        dateFilter = .all
        selectedNoteID = nil
        selection = .section(section.id)
    }

    private func clearHiddenSelection() {
        if let selectedNote, !filter.matches(selectedNote) {
            selectedNoteID = nil
        }
        selectFirstIfNeeded()
    }

    /// Görünür bir not varsa editör boş kalmasın: listenin ilk notunu seç.
    private func selectFirstIfNeeded() {
        guard selectedNoteID == nil else { return }
        let visible = filter.apply(to: allNotes)
        if filter.isTrash {
            selectedNoteID = visible.max { ($0.deletedAt ?? .distantPast) < ($1.deletedAt ?? .distantPast) }?.id
            return
        }
        let ordered = DateGrouping.groups(for: visible, now: filter.now, calendar: filter.calendar).flatMap(\.notes)
        selectedNoteID = ordered.first?.id
    }

    private func addNote(template: NoteTemplate) {
        if selection == .trash || selection.map({ if case .tag = $0 { true } else { false } }) == true {
            selection = .smart(.all)
        }
        searchText = ""
        let section = context.sectionForNewNote(selection: selection)
        let note = context.addNote(from: template, in: section)
        if let selection, !selection.includes(note, now: .now) || selection.isView { self.selection = .section(section.id) }
        if !filter.matches(note) { dateFilter = .all }
        selectedNoteID = note.id
    }

    /// `section` verilmezse seçime göre (seçili bölüm → defterin ilk bölümü → ilk defter).
    private func addNote(in section: NoteSection? = nil) {
        if selection == .trash { selection = .smart(.all) }
        searchText = ""
        let section = section ?? context.sectionForNewNote(selection: selection)
        let note = context.addNote(in: section)
        if let selection, !selection.includes(note, now: .now) || selection.isView {
            self.selection = .section(section.id)
        }
        if !filter.matches(note) {
            dateFilter = .all
        }
        selectedNoteID = note.id
    }
}

#if DEBUG
#Preview("Light") {
    ContentView()
        .modelContainer(SampleData.container())
        .frame(width: 1140, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .modelContainer(SampleData.container())
        .frame(width: 1140, height: 700)
        .preferredColorScheme(.dark)
}
#endif
