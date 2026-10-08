import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Folio

/// Görsel kontrol için PNG üretir. Yalnızca `TEST_RUNNER_SNAPSHOT_DIR` verildiğinde çalışır.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
struct SnapshotTests {
    let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: ["light", "dark"])
    func mainWindow(appearance: String) throws {
        let container = SampleData.container()
        let view = ContentView()
            .modelContainer(container)
            .frame(width: 1140, height: 720)
        try render(view, size: CGSize(width: 1140, height: 720), name: "window-\(appearance)", dark: appearance == "dark")
    }

    @Test func searchResults() throws {
        let container = SampleData.container()
        let view = ContentView(searchText: "login")
            .modelContainer(container)
            .frame(width: 1140, height: 720)
        try render(view, size: CGSize(width: 1140, height: 720), name: "search-light", dark: false)
    }

    @Test(arguments: ["light", "dark"])
    func editorWithTable(appearance: String) throws {
        let view = ContentView()
            .modelContainer(SampleData.container())
            .frame(width: 1140, height: 1500)
        try render(view, size: CGSize(width: 1140, height: 1500), name: "editor-table-\(appearance)", dark: appearance == "dark")
    }

    @Test(arguments: ["light", "dark"])
    func formatBarAndLiveEditor(appearance: String) throws {
        let controller = MarkdownEditorController()
        let text = "## Bu hafta\n\nAuth akışı **AuthService** üzerinden, `refresh` *sonra*.\n\n- [x] Login\n- [ ] API\n1. bir\n> not\n\n| İş | Sahip |\n| --- | --- |\n| API | Talha |"
        let view = VStack(spacing: 0) {
            EditorFormatBar(controller: controller, currentStyle: .heading2, textSizeRaw: .constant(1), onInsertTable: {}, onDone: {})
            MarkdownTextEditor(text: .constant(text), scale: 1, controller: controller)
                .padding(40)
            Spacer()
        }
        .frame(width: 760, height: 560)
        .background(Color.ds.surface)
        try render(view, size: CGSize(width: 760, height: 560), name: "format-bar-\(appearance)", dark: appearance == "dark")
    }

    @Test func tableEditorSheet() throws {
        let view = TableEditorView(table: .empty(columns: 3, rows: 3), isNew: true) { _ in }
            .frame(width: 920, height: 620)
            .background(Color.ds.surface)
        try render(view, size: CGSize(width: 920, height: 620), name: "table-editor-light", dark: false)
    }

    @Test func editingNoteDark() throws {
        let container = SampleData.container()
        let note = Note(title: "")
        container.mainContext.insert(note)
        note.body = "Bu cümlede **kalın**, *italik* ve `kod` var.\n\n- madde bir\n- madde iki\n1. birinci\n2. ikinci"
        let view = NavigationStack { NoteEditorView(note: note, startsEditingBody: true) }
            .modelContainer(container)
        // Kaydırma alanlı editör, tam boyutlu içerik penceresinde boş çiziliyor; düz pencere kullanılır.
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)); hosting.layoutSubtreeIfNeeded() }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: directory.appending(path: "editing-dark.png"))
    }

    @Test func nameSheetWithDuplicate() throws {
        let view = NameSheet(
            kind: .notebook, title: "Yeni Defter", confirmTitle: "Oluştur", initialName: "iş",
            existingNames: ["İş", "Kişisel"], initialColor: .slate
        ) { _, _ in }
        .background(Color.ds.surfaceRaised)
        try render(view, size: CGSize(width: 340, height: 220), name: "name-sheet-light", dark: false)
    }

    @Test(arguments: ["light", "dark"])
    func settings(appearance: String) throws {
        try render(GeneralSettingsView().frame(width: 520), size: CGSize(width: 520, height: 300), name: "settings-general-\(appearance)", dark: appearance == "dark")
        try render(ImportSettingsView().frame(width: 520), size: CGSize(width: 520, height: 400), name: "settings-import-\(appearance)", dark: appearance == "dark")
    }

    @Test func themePicker() throws {
        let view = ThemePicker().padding(16).frame(width: 300).background(Color.ds.surfaceRaised)
        try render(view, size: CGSize(width: 300, height: 200), name: "theme-picker-light", dark: false)
    }

    @Test(arguments: ["board", "calendar"])
    func views(name: String) throws {
        let view = ContentView(viewMode: name == "board" ? .board : .calendar)
            .modelContainer(SampleData.container())
            .frame(width: 1240, height: 720)
        try render(view, size: CGSize(width: 1240, height: 720), name: "view-\(name)", dark: false)
    }

    @Test(arguments: ["light", "dark"])
    func commandPalette(appearance: String) throws {
        let view = ContentView(showsPalette: true)
            .modelContainer(SampleData.container())
            .frame(width: 1240, height: 720)
        try render(view, size: CGSize(width: 1240, height: 720), name: "palette-\(appearance)", dark: appearance == "dark")
    }

    @Test func compactList() throws {
        UserDefaults.standard.set(ListDensity.compact.rawValue, forKey: ListDensity.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: ListDensity.storageKey) }
        let view = ContentView()
            .modelContainer(SampleData.container())
            .frame(width: 1240, height: 720)
        try render(view, size: CGSize(width: 1240, height: 720), name: "list-compact", dark: false)
    }

    @Test func trash() throws {
        let container = SampleData.container()
        let view = ContentView(selection: .trash)
            .modelContainer(container)
            .frame(width: 1140, height: 720)
        try render(view, size: CGSize(width: 1140, height: 720), name: "trash-light", dark: false)
    }

    @Test(arguments: ["light", "dark"])
    func sidebar(appearance: String) throws {
        let container = SampleData.container()
        let view = SidebarView(selection: .constant(.smart(.all)), expanded: .constant([]))
            .modelContainer(container)
            .frame(width: Metrics.Layout.sidebarWidth, height: 520)
        try render(view, size: CGSize(width: Metrics.Layout.sidebarWidth, height: 520), name: "sidebar-\(appearance)", dark: appearance == "dark")
    }

    private func render(_ view: some View, size: CGSize, name: String, dark: Bool) throws {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appending(path: "\(name).png"))
        window.orderOut(nil)
    }
}
