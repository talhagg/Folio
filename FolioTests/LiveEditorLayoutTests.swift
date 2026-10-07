import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Folio

/// Regresyon: SwiftUI 0 genişlik önerince metin kutusu 0'a ayarlanıyor ve yazılanlar görünmüyordu.
@MainActor
struct LiveEditorLayoutTests {
    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.delegate is MarkdownTextEditor.Coordinator { return textView }
        for subview in view.subviews { if let found = findTextView(in: subview) { return found } }
        return nil
    }

    @Test func bodyTextIsLaidOutInsideTheVisibleWidth() throws {
        let container = ModelContainer.folioInMemory()
        let note = Note(title: "")
        container.mainContext.insert(note)
        note.body = "- madde bir\n- madde iki"
        let view = NavigationStack { NoteEditorView(note: note, startsEditingBody: true) }.modelContainer(container)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)); hosting.layoutSubtreeIfNeeded() }

        let textView = try #require(findTextView(in: hosting))
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        #expect(textContainer.containerSize.width == textView.frame.width)
        #expect(textView.frame.width > 300)
        #expect(used.width <= textView.frame.width)
        #expect(used.height > 20)
        // İki satır üst üste değil, alt alta dizilmiş olmalı.
        #expect(layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: nil).minY > 0)
    }

    @Test func measuredHeightGrowsWithLines() {
        let one = NSAttributedString(string: "bir", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let three = NSAttributedString(string: "bir\niki\nüç", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        #expect(MarkdownTextEditor.measuredHeight(of: three, width: 400) > MarkdownTextEditor.measuredHeight(of: one, width: 400) * 2)
    }
}
