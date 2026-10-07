import SwiftData
import SwiftUI

/// 3 sütunlu ana pencere: kenar çubuğu → not listesi → editör.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var isThemePickerShown = false

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

    init(selection: SidebarSelection = .smart(.all), searchText: String = "") {
        self._selection = State(initialValue: selection)
        self._searchText = State(initialValue: searchText)
    }

    private var filter: NoteFilter {
        NoteFilter(selection: selection, dateFilter: dateFilter, searchText: searchText, now: .now)
    }

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
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                newNotebookRequest: newNotebookRequest,
                onNewNote: { addNote(in: $0) },
                onImportFiles: { isFileImporterShown = true },
                onImportURL: { isURLImportShown = true },
                onExport: { notes, name in export(notes, as: .json, fallbackName: name) }
            )
                .persistWidth(key: WindowLayout.sidebarWidthKey)
                .navigationSplitViewColumnWidth(
                    min: Metrics.Layout.sidebarMinWidth,
                    ideal: sidebarWidth,
                    max: Metrics.Layout.sidebarMaxWidth
                )
        } content: {
            NoteListView(
                filter: filter,
                dateFilter: $dateFilter,
                selectedNoteID: $selectedNoteID,
                onClearSearch: { searchText = "" },
                onDelete: { deleteRequest = $0 },
                onExport: { note, format in export([note], as: format) }
            )
            .persistWidth(key: WindowLayout.listWidthKey)
            // fileImporter ile aynı görünümde olursa biri çalışmıyor; dışa aktarma liste sütununda.
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
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                importFiles(files)
                return true
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: listWidth, max: 420)
        } detail: {
            detail
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Notlarda ara"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isThemePickerShown.toggle()
                } label: {
                    Label("Tema", systemImage: "paintpalette")
                }
                .help(Text("Tema: görünüm ve vurgu rengi"))
                .popover(isPresented: $isThemePickerShown, arrowEdge: .bottom) {
                    ThemePicker()
                        .padding(Metrics.Spacing.s4)
                        .frame(width: 300)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { addNote() } label: {
                    Label("Yeni Not", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ds.accent)
                .help(Text("Yeni not oluştur (⌘N)"))
            }
        }
        .focusedSceneValue(\.noteActions, commandActions)
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

    @ViewBuilder
    private var detail: some View {
        if let selectedNote {
            NoteEditorView(
                note: selectedNote,
                onDeletePermanently: { deleteRequest = selectedNote },
                onExport: { export([selectedNote], as: $0) }
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
            importFiles: { isFileImporterShown = true },
            importURL: { isURLImportShown = true },
            exportNote: exportNote,
            exportAll: exportAll
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

    /// `section` verilmezse seçime göre (seçili bölüm → defterin ilk bölümü → ilk defter).
    private func addNote(in section: NoteSection? = nil) {
        if selection == .trash { selection = .smart(.all) }
        searchText = ""
        let section = section ?? context.sectionForNewNote(selection: selection)
        let note = context.addNote(in: section)
        if let selection, !selection.includes(note, now: .now) {
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
