import CoreSpotlight
import Foundation
import SwiftData
import Testing
@testable import Folio

@MainActor
struct SystemIntegrationTests {
    @Test func spotlightItemDescribesNote() {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let notebook = context.addNotebook(name: "İş")
        let note = context.addNote(in: context.addSection(name: "Sprint", to: notebook), title: "Plan")
        note.body = "## Hedef\n**Login** bitecek #ios"
        let item = SpotlightIndexer.item(for: note)
        #expect(item.uniqueIdentifier == note.id.uuidString)
        #expect(item.domainIdentifier == SpotlightIndexer.domain)
        #expect(item.attributeSet.title == "Plan")
        #expect(item.attributeSet.contentDescription == "Hedef Login bitecek #ios")
        #expect(Set(item.attributeSet.keywords ?? []) == ["ios", "İş", "Sprint"])
    }

    @Test func spotlightActivityRoutesToNote() {
        let id = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]
        #expect(SpotlightIndexer.noteID(from: activity) == id)
        #expect(SpotlightIndexer.noteID(from: NSUserActivity(activityType: "başka")) == nil)
    }

    @Test func addNoteIntentCreatesNote() async throws {
        let container = ModelContainer.folioInMemory()
        let previous = QuickActions.shared.container
        QuickActions.shared.container = container
        defer { QuickActions.shared.container = previous }

        var intent = AddNoteIntent()
        intent.noteTitle = "Kısayoldan"
        intent.content = "gövde"
        _ = try await intent.perform()
        let notes = try container.mainContext.fetch(FetchDescriptor<Note>())
        #expect(notes.map(\.title) == ["Kısayoldan"])
        #expect(notes.first?.body == "gövde")

        let found = try await NoteEntityQuery().entities(matching: "kısayol")
        #expect(found.map(\.title) == ["Kısayoldan"])
    }
}
