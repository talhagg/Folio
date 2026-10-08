import AppKit
import Foundation
import Testing
@testable import Folio

/// Gerçek ağ gerektirir; yalnızca LIVE_URL_TESTS ortam değişkeniyle çalışır.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_URL_TESTS"] != nil))
struct LiveWebImportTests {
    private func load(_ address: String) async throws -> (String, String) {
        let page = WebPage(url: URL(string: address)!)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = page.webView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
            if !page.isLoading { break }
        }
        try await Task.sleep(for: .milliseconds(800))
        let snapshot = try await page.contentSnapshot()
        let result = HTMLToMarkdown.convert(html: snapshot.html)
        return (WebPage.cleanTitle(snapshot.title) ?? "", result.markdown)
    }

    @Test func importsSimplePage() async throws {
        let (title, markdown) = try await load("https://example.com")
        print("WEB example:", title, "|", markdown.prefix(160))
        #expect(title == "Example Domain")
        #expect(markdown.contains("documentation"))
    }

    @Test func importsPageWithTables() async throws {
        let (title, markdown) = try await load("https://en.wikipedia.org/wiki/List_of_countries_by_population_(United_Nations)")
        let blocks = MarkdownDocument.parse(markdown)
        let tables = blocks.filter { if case .table = $0.block { true } else { false } }
        print("WEB wiki:", title, "| bloklar:", blocks.count, "| tablolar:", tables.count, "|", markdown.prefix(200).replacingOccurrences(of: "\n", with: " ⏎ "))
        #expect(!tables.isEmpty)
    }
}
