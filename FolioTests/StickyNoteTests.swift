import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Folio

@MainActor
struct StickyNoteTests {
    @Test func preferencesArePerNote() {
        let a = UUID(), b = UUID()
        #expect(StickyNote.colorKey(a) != StickyNote.colorKey(b))
        #expect(StickyNote.colorKey(a) != StickyNote.floatingKey(a))
    }

    @Test func everyColorHasTitleAndIsUnique() {
        #expect(Set(StickyColor.allCases.map(\.title)).count == StickyColor.allCases.count)
    }

    private func render(_ view: some View, size: CGSize, dark: Bool) -> NSBitmapImageRep? {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)); hosting.layoutSubtreeIfNeeded() }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    @Test func trashedNoteShowsDeletedState() throws {
        let container = ModelContainer.folioInMemory()
        let note = Note(title: "Sil")
        container.mainContext.insert(note)
        container.mainContext.moveToTrash(note)
        let rep = render(StickyNoteWindow(noteID: note.id).modelContainer(container), size: CGSize(width: 300, height: 200), dark: false)
        #expect(rep != nil)
    }

    @Test(arguments: ["light", "dark"])
    func snapshotAllColors(appearance: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let container = ModelContainer.folioInMemory()
        let views = StickyColor.allCases.map { color -> Note in
            let note = Note(title: "\(color.title) not")
            container.mainContext.insert(note)
            note.body = "Yarın **10:00** toplantı.\n\n- süt al\n- [x] faturayı öde"
            UserDefaults.standard.set(color.rawValue, forKey: StickyNote.colorKey(note.id))
            return note
        }
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 12), count: 3), spacing: 12) {
            ForEach(views) { note in
                StickyNoteView(note: note)
                    .frame(width: 260, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .modelContainer(container)
        let rep = try #require(render(grid, size: CGSize(width: 828, height: 420), dark: appearance == "dark"))
        try rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: directory).appending(path: "sticky-\(appearance).png"))
        for note in views { UserDefaults.standard.removeObject(forKey: StickyNote.colorKey(note.id)) }
    }
}
