import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Folio

/// Toolbar içerik değişince kaymamalı: öğeler her görünümde aynı ve aynı sırada.
@MainActor
struct ToolbarTests {
    private func window(for selection: SidebarSelection) -> NSWindow {
        let controller = NSHostingController(rootView: ContentView(selection: selection).modelContainer(SampleData.container()))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1180, height: 720))
        window.makeKeyAndOrderFront(nil)
        let end = Date().addingTimeInterval(1.2)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return window
    }

    private func labels(_ window: NSWindow) -> [String] {
        // Arama alanı gibi özel görünümlerin kimliği her pencerede rastgele; türüyle karşılaştır.
        (window.toolbar?.items ?? []).map { $0.label.isEmpty ? "özel görünüm" : $0.label }
    }

    @Test func toolbarItemsAreStableAcrossViews() throws {
        let notes = window(for: .smart(.all))
        let trash = window(for: .trash)
        defer { notes.orderOut(nil); trash.orderOut(nil) }
        let withNote = labels(notes)
        let inTrash = labels(trash)
        print("TOOLBAR notes:", withNote)
        print("TOOLBAR trash:", inTrash)
        #expect(!withNote.isEmpty)
        #expect(withNote == inTrash)
        #expect(withNote == ["özel görünüm", "Dışa Aktar", "Tema", "Yeni Not"])

        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let frame = notes.contentView?.superview,
           let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: directory).appending(path: "toolbar-window.png"))
        }
    }
}
