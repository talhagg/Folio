import SwiftData
import SwiftUI

@main
struct FolioApp: App {
    let container = ModelContainer.folioForApp()

    init() {
        ThemeStore.shared.applyAppearance()
        #if DEBUG
        // Scheme'deki `-seedSampleData` argümanıyla boş depoya örnek veri yüklenir.
        if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
            SampleData.seedIfEmpty(container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color.ds.accent)
        }
        .defaultSize(width: 1140, height: 700)
        .modelContainer(container)
        .commands { AppCommands() }

        Settings {
            SettingsView()
                .tint(Color.ds.accent)
        }
    }
}
