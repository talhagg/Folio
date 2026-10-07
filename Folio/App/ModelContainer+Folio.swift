import Foundation
import OSLog
import Security
import SwiftData

extension ModelContainer {
    static let cloudKitContainerID = "iCloud.com.talha.folio"

    static var folioSchema: Schema {
        Schema([Notebook.self, NoteSection.self, Note.self, NoteTask.self])
    }

    /// iCloud özel veritabanıyla senkronlanan kalıcı depo.
    static func folioCloud() throws -> ModelContainer {
        let config = ModelConfiguration(
            "Folio",
            schema: folioSchema,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        return try ModelContainer(for: folioSchema, configurations: config)
    }

    /// Senkronsuz yerel depo (entitlement'sız ad-hoc derlemeler için).
    static func folioLocal() throws -> ModelContainer {
        let config = ModelConfiguration("Folio", schema: folioSchema, cloudKitDatabase: .none)
        return try ModelContainer(for: folioSchema, configurations: config)
    }

    /// Preview ve testler için.
    static func folioInMemory() -> ModelContainer {
        let config = ModelConfiguration(
            schema: folioSchema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: folioSchema, configurations: config)
        } catch {
            fatalError("In-memory ModelContainer oluşturulamadı: \(error)")
        }
    }

    /// Uygulamanın kullandığı container: testte bellek içi, iCloud entitlement'ı varsa CloudKit, yoksa yerel.
    static func folioForApp() -> ModelContainer {
        let log = Logger(subsystem: "com.talha.folio", category: "Persistence")
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return folioInMemory()
        }
        if hasCloudKitEntitlement {
            do {
                return try folioCloud()
            } catch {
                log.error("CloudKit container açılamadı, yerel depoya geçiliyor: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            log.notice("iCloud entitlement'ı yok; yerel depo kullanılıyor.")
        }
        do {
            return try folioLocal()
        } catch {
            fatalError("Yerel ModelContainer oluşturulamadı: \(error)")
        }
    }

    private static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        return (value as? [String])?.contains("CloudKit") ?? false
    }
}
