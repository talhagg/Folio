import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Folio

@MainActor
struct QuickNoteTests {
    @Test func firstLineBecomesTitleRestBecomesBody() {
        let container = ModelContainer.folioInMemory()
        let note = QuickActions.shared.addQuickNote(text: "  Market\nsüt\nekmek \n", in: container.mainContext)
        #expect(note.title == "Market")
        #expect(note.body == "süt\nekmek")
        #expect(note.section != nil)
    }

    @Test func usesChosenSectionWhenSaved() {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let notebook = context.addNotebook(name: "Gelen")
        let inbox = context.addSection(name: "Kutu", to: notebook)
        try? context.save()
        UserDefaults.standard.set(inbox.id.uuidString, forKey: QuickActions.sectionKey)
        defer { UserDefaults.standard.removeObject(forKey: QuickActions.sectionKey) }
        #expect(QuickActions.shared.targetSection(in: context) === inbox)
    }

    @Test func quickNotePanelRenders() throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let view = QuickNoteView().modelContainer(SampleData.container()).background(Color.ds.surfaceRaised)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)); hosting.layoutSubtreeIfNeeded() }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(filePath: directory).appending(path: "quick-note.png"))
    }
}
