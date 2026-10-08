import SwiftData
import SwiftUI

@main
struct FolioApp: App {
    let container = ModelContainer.folioForApp()

    init() {
        ThemeStore.shared.applyAppearance()
        QuickActions.shared.container = container
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            ReminderScheduler.shared.start(container: container)
            SpotlightIndexer.shared.start(container: container)
            GlobalHotKey.shared.setEnabled(UserDefaults.standard.object(forKey: QuickActions.hotKeyEnabledKey) as? Bool ?? true)
        }
        #if DEBUG
        // Scheme'deki `-seedSampleData` argümanıyla boş depoya örnek veri yüklenir.
        if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
            SampleData.seedIfEmpty(container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .tint(Color.ds.accent)
                // folio:// bağlantıları yeni pencere açmasın, mevcut pencereye gitsin.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1140, height: 700)
        .modelContainer(container)
        .commands { AppCommands() }

        // Yapışkan notlar: not başına küçük pencere; açık olanlar yeniden başlatınca geri gelir.
        WindowGroup("Yapışkan Not", id: StickyNote.windowID, for: UUID.self) { $noteID in
            if let noteID {
                StickyNoteWindow(noteID: noteID)
                    .tint(Color.ds.accent)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 300, height: 320)
        .commandsRemoved()
        .modelContainer(container)

        // Menü çubuğundan hızlı not.
        MenuBarExtra {
            QuickNoteView()
                .modelContainer(container)
        } label: {
            QuickNoteMenuLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .tint(Color.ds.accent)
        }
    }
}
