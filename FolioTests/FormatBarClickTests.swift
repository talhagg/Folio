import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Folio

/// Biçim çubuğundaki düğmelere gerçek fare ve klavye olaylarıyla basar.
/// Regresyon: tıklama SwiftUI'yi senkron güncelliyor, eski metin editörü eziyor ve imleç kalın çiftin dışına düşüyordu.
@MainActor
struct FormatBarClickTests {
    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.delegate is MarkdownTextEditor.Coordinator { return textView }
        for subview in view.subviews { if let found = findTextView(in: subview) { return found } }
        return nil
    }



    private func pump(_ hosting: NSView, _ seconds: Double = 0.4) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); hosting.layoutSubtreeIfNeeded() }
    }

    private func clickAt(_ point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
            window.sendEvent(event)
        }
    }

    private func type(_ text: String, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) {
        for character in text {
            let string = String(character)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: string,
                    charactersIgnoringModifiers: string, isARepeat: false, keyCode: 0
                )!
                if modifiers.contains(.command) && type == .keyDown {
                    if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
                } else {
                    window.sendEvent(event)
                }
            }
        }
    }

    private func snapshot(_ hosting: NSView, _ name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"],
              let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: directory).appending(path: name))
    }


    @Test func clickingBoldWithSelectedWord() throws {
        let container = ModelContainer.folioInMemory()
        let note = Note(title: "Deneme")
        container.mainContext.insert(note)
        note.body = "merhaba dünya"
        let view = NavigationStack { NoteEditorView(note: note, startsEditingBody: true) }.modelContainer(container)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        pump(hosting, 1)

        let textView = try #require(findTextView(in: hosting))
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 8, length: 5))
        pump(hosting)

        // Biçim çubuğunda B düğmesi: soldan ~154 pt, üstten ~20 pt (snapshot'tan).
        let local = NSPoint(x: 154, y: hosting.isFlipped ? 20 : hosting.bounds.height - 20)
        let point = hosting.convert(local, to: nil)
        clickAt(point, in: window)
        pump(hosting)
        #expect(note.body == "merhaba **dünya**")

        // 2) Seçim yokken: sona git, B'ye tıkla, klavyeden yaz, tekrar B, yaz.
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        type(" ", in: window)
        clickAt(point, in: window)
        pump(hosting)
        type("kalın ", in: window)
        pump(hosting)
        // Boşluk konduğu an: yıldızlar gizli, metin kalın kalmalı.
        let storage = try #require(textView.textStorage)
        let closing = (textView.string as NSString).length - 1
        let markerFont = try #require(storage.attribute(.font, at: closing, effectiveRange: nil) as? NSFont)
        #expect(markerFont.pointSize < 1)
        try snapshot(hosting, "click-space.png")
        type("yazı", in: window)
        clickAt(point, in: window)
        pump(hosting)
        type(" normal", in: window)
        pump(hosting)
        #expect(note.body == "merhaba **dünya** **kalın yazı** normal")

        // 3) ⌘I kısayolu, seçim yokken.
        type(" ", in: window)
        type("i", in: window, modifiers: .command)
        pump(hosting)
        type("egik", in: window)
        pump(hosting)
        #expect(note.body == "merhaba **dünya** **kalın yazı** normal *egik*")
        try snapshot(hosting, "click-flow.png")
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView?.frame.height ?? 0 > scroll.contentView.bounds.height { return scroll }
        for subview in view.subviews { if let found = findScrollView(in: subview) { return found } }
        return nil
    }

    /// Biçim çubuğu düzenleme kapalıyken de görünür; B'ye basmak düzenlemeyi başlatıp kalın yazdırır.
    @Test func boldWhileNotEditingStartsEditing() throws {
        let container = ModelContainer.folioInMemory()
        let note = Note(title: "Deneme")
        container.mainContext.insert(note)
        note.body = "merhaba"
        let view = NavigationStack { NoteEditorView(note: note) }.modelContainer(container)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        pump(hosting, 1)
        #expect(findTextView(in: hosting) == nil)

        let local = NSPoint(x: 154, y: hosting.isFlipped ? 20 : hosting.bounds.height - 20)
        clickAt(hosting.convert(local, to: nil), in: window)
        pump(hosting, 0.8)
        let textView = try #require(findTextView(in: hosting))
        // Test penceresi anahtar olamadığından odağı elle doğrula.
        if window.firstResponder !== textView { window.makeFirstResponder(textView) }
        type("yeni", in: window)
        pump(hosting)
        #expect(note.body.hasSuffix("**yeni**"))
    }

    /// Uzun notta aşağı kaydırınca çubuk yerinde kalır ve notun adını gösterir.
    @Test func stickyBarShowsTitleWhenScrolled() throws {
        let container = ModelContainer.folioInMemory()
        let note = Note(title: "Uzun bir not")
        container.mainContext.insert(note)
        note.body = (1...80).map { "Satır \($0) — biraz metin." }.joined(separator: "\n\n")
        let view = NavigationStack { NoteEditorView(note: note) }.modelContainer(container)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        pump(hosting, 1)

        let scroll = try #require(findScrollView(in: hosting))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 900))
        scroll.reflectScrolledClipView(scroll.contentView)
        pump(hosting, 0.8)
        try snapshot(hosting, "sticky-bar-scrolled.png")

    }
}
