import AppKit
import SwiftUI
import Testing
@testable import Folio

@MainActor
struct PaletteRankerTests {
    private func item(_ title: String, keywords: String = "", subtitle: String = "") -> PaletteItem {
        PaletteItem(id: title, kind: .command, title: title, subtitle: subtitle, symbolName: "circle", keywords: keywords, perform: {})
    }

    @Test func prefixBeatsSubstringBeatsFuzzy() {
        let items = [item("Notlarda Ara"), item("Yeni Not"), item("Not Listesi: Sade"), item("Son Silinenler")]
        let ranked = PaletteRanker.rank(items, query: "not").map(\.title)
        #expect(ranked.first == "Not Listesi: Sade")
        #expect(ranked.contains("Yeni Not"))
        #expect(!ranked.contains("Son Silinenler"))
    }

    @Test func ignoresCaseAndTurkishDiacritics() {
        #expect(PaletteRanker.score(query: "sablon", in: "Şablondan Yeni Not") != nil)
        #expect(PaletteRanker.score(query: "İÇE", in: "Dosyadan içe aktar") != nil)
        #expect(PaletteRanker.score(query: "yapiskan", in: "Yeni Yapışkan Not") != nil)
    }

    @Test func fuzzySubsequenceMatches() {
        #expect(PaletteRanker.score(query: "ynt", in: "Yeni Not") != nil)
        #expect(PaletteRanker.score(query: "xyz", in: "Yeni Not") == nil)
    }

    @Test func keywordsMatchWithLowerScore() {
        let items = [item("Tema: Koyu", keywords: "görünüm açık koyu"), item("Görünüm: Pano")]
        let ranked = PaletteRanker.rank(items, query: "görünüm").map(\.title)
        #expect(ranked == ["Görünüm: Pano", "Tema: Koyu"])
    }

    @Test func stableOrderOnEqualScore() {
        let items = [item("Alfa Bir"), item("Alfa İki")]
        #expect(PaletteRanker.rank(items, query: "alfa").map(\.title) == ["Alfa Bir", "Alfa İki"])
    }
}

/// Paleti gerçek klavye olaylarıyla kullanır: yaz, ↓, ↩.
@MainActor
struct CommandPaletteKeyTests {
    private func pump(_ view: NSView, _ seconds: Double = 0.4) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); view.layoutSubtreeIfNeeded() }
    }

    private func key(_ characters: String, code: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
            )!
            window.sendEvent(event)
        }
    }

    @Test func typeArrowAndReturnRunsSecondResult() throws {
        final class Box { var ran: [String] = []; var dismissed = false }
        let box = Box()
        let items = ["Görünüm: Liste", "Görünüm: Pano", "Görünüm: Takvim", "Yeni Not"].map { title in
            PaletteItem(id: title, kind: .command, title: title, symbolName: "circle", perform: { box.ran.append(title) })
        }
        let view = CommandPaletteView(items: items, suggestions: items, onDismiss: { box.dismissed = true })
            .padding(20)
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 640, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        pump(hosting, 0.8)

        // Test penceresi anahtar pencere olamıyor (uygulama arka planda); alanı elle odakla.
        func find(_ v: NSView) -> NSTextField? { (v as? NSTextField) ?? v.subviews.lazy.compactMap(find).first }
        window.makeFirstResponder(try #require(find(hosting)))
        pump(hosting)
        for character in "görünüm" { key(String(character), code: 0, in: window) }
        pump(hosting)
        key(String(UnicodeScalar(NSDownArrowFunctionKey)!), code: 125, in: window)
        pump(hosting)
        key("\r", code: 36, in: window)
        pump(hosting)

        #expect(box.ran == ["Görünüm: Pano"])
        #expect(box.dismissed)
    }

    @Test func escapeDismisses() throws {
        final class Box { var dismissed = false }
        let box = Box()
        let view = CommandPaletteView(items: [], suggestions: [], onDismiss: { box.dismissed = true })
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 640, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        pump(hosting, 0.8)
        func find(_ v: NSView) -> NSTextField? { (v as? NSTextField) ?? v.subviews.lazy.compactMap(find).first }
        window.makeFirstResponder(try #require(find(hosting)))
        pump(hosting)
        key("\u{1b}", code: 53, in: window)
        pump(hosting)
        #expect(box.dismissed)
    }
}
