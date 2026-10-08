import AppIntents
import Foundation
import SwiftData

/// Kısayollar / Siri için not varlığı.
struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Not"
    static let defaultQuery = NoteEntityQuery()

    let id: UUID
    let title: String
    let location: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title.isEmpty ? String(localized: "Başlıksız not") : title)",
            subtitle: location.map { "\($0)" }
        )
    }

    @MainActor
    init(_ note: Note) {
        id = note.id
        title = note.title
        location = note.locationPath
    }
}

struct NoteEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        IntentStore.notes().filter { identifiers.contains($0.id) }.map(NoteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [NoteEntity] {
        IntentStore.notes().filter { NoteFilter.matchesSearch($0, query: string) }.prefix(30).map(NoteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteEntity] {
        IntentStore.notes().prefix(10).map(NoteEntity.init)
    }
}

@MainActor
enum IntentStore {
    static var context: ModelContext {
        if QuickActions.shared.container == nil { QuickActions.shared.container = ModelContainer.folioForApp() }
        return QuickActions.shared.container!.mainContext
    }

    /// Çöpte olmayan notlar, en son düzenlenen önce.
    static func notes() -> [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isTrashed }
    }
}

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Folio'ya Not Ekle"
    static let description = IntentDescription("Hızlı not bölümüne yeni bir not ekler.")

    @Parameter(title: "Başlık")
    var noteTitle: String

    @Parameter(title: "İçerik")
    var content: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$noteTitle) notunu ekle") { \.$content }
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<NoteEntity> & ProvidesDialog {
        let text = [noteTitle, content ?? ""].joined(separator: "\n")
        let note = QuickActions.shared.addQuickNote(text: text, in: IntentStore.context)
        return .result(value: NoteEntity(note), dialog: "\"\(note.title)\" Folio'ya eklendi.")
    }
}

struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Folio'da Notu Aç"
    static let openAppWhenRun = true

    @Parameter(title: "Not")
    var note: NoteEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActions.shared.openMain(.note(note.id))
        return .result()
    }
}

struct SearchNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Folio'da Not Ara"
    static let description = IntentDescription("Başlık, içerik ve görevlerde arar.")

    @Parameter(title: "Aranan")
    var query: String

    @MainActor
    func perform() async throws -> some ReturnsValue<[NoteEntity]> {
        .result(value: IntentStore.notes().filter { NoteFilter.matchesSearch($0, query: query) }.prefix(30).map(NoteEntity.init))
    }
}

struct FolioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddNoteIntent(),
            phrases: ["\(.applicationName) ile not ekle", "\(.applicationName) notu ekle"],
            shortTitle: "Not Ekle",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: ["\(.applicationName) ile \(\.$note) notunu aç"],
            shortTitle: "Notu Aç",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: ["\(.applicationName) ile not ara"],
            shortTitle: "Not Ara",
            systemImageName: "magnifyingglass"
        )
    }
}
