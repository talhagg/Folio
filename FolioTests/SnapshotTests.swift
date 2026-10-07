import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Folio

/// Görsel kontrol için PNG üretir. Yalnızca `TEST_RUNNER_SNAPSHOT_DIR` verildiğinde çalışır.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
struct SnapshotTests {
    let directory = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: ["light", "dark"])
    func mainWindow(appearance: String) throws {
        let container = SampleData.container()
        let view = ContentView()
            .modelContainer(container)
            .frame(width: 1140, height: 720)
        try render(view, size: CGSize(width: 1140, height: 720), name: "window-\(appearance)", dark: appearance == "dark")
    }

    @Test func searchResults() throws {
        let container = SampleData.container()
        let view = ContentView(searchText: "login")
            .modelContainer(container)
            .frame(width: 1140, height: 720)
        try render(view, size: CGSize(width: 1140, height: 720), name: "search-light", dark: false)
    }

    @Test func trash() throws {
        let container = SampleData.container()
        let view = ContentView(selection: .trash)
            .modelContainer(container)
            .frame(width: 1140, height: 720)
        try render(view, size: CGSize(width: 1140, height: 720), name: "trash-light", dark: false)
    }

    @Test(arguments: ["light", "dark"])
    func sidebar(appearance: String) throws {
        let container = SampleData.container()
        let view = SidebarView(selection: .constant(.smart(.all)))
            .modelContainer(container)
            .frame(width: Metrics.Layout.sidebarWidth, height: 520)
        try render(view, size: CGSize(width: Metrics.Layout.sidebarWidth, height: 520), name: "sidebar-\(appearance)", dark: appearance == "dark")
    }

    private func render(_ view: some View, size: CGSize, name: String, dark: Bool) throws {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appending(path: "\(name).png"))
        window.orderOut(nil)
    }
}
