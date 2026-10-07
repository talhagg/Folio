import Foundation
import Testing
@testable import Folio

struct SearchTests {
    @Test func rangesAreCaseAndDiacriticInsensitive() {
        let text = "Login ekranı ve LOGIN akışı"
        let ranges = SearchHighlighter.ranges(of: "login", in: text)
        #expect(ranges.map { String(text[$0]) } == ["Login", "LOGIN"])
        #expect(SearchHighlighter.ranges(of: "akisi", in: text).count == 1)
        #expect(SearchHighlighter.ranges(of: "", in: text).isEmpty)
    }

    @Test func turkishDottedAndDotlessIAreEquivalent() {
        #expect(SearchHighlighter.contains("İzmir", "izmir"))
        #expect(SearchHighlighter.contains("ışık", "ISIK"))
        #expect(SearchHighlighter.contains("API bağlantısı", "api"))
        #expect(!SearchHighlighter.contains("Sprint", "sprınt x"))
        let text = "Bağlantı: İstanbul"
        let ranges = SearchHighlighter.ranges(of: "istanbul", in: text)
        #expect(ranges.map { String(text[$0]) } == ["İstanbul"])
    }

    @Test func attributedMarksEveryMatch() {
        let attributed = SearchHighlighter.attributed("api ve API", query: "api")
        let highlighted = attributed.runs.filter { $0.backgroundColor != nil }.count
        #expect(highlighted == 2)
        #expect(String(attributed.characters) == "api ve API")
    }

    @Test func snippetWithoutQueryIsBodyStart() {
        #expect(SearchSnippet.preview(body: "# Başlık\nMetin", taskTexts: [], query: "") == "Başlık Metin")
    }

    @Test func snippetCentersOnDeepMatch() {
        let body = String(repeating: "dolgu kelime ", count: 20) + "interceptor eklenecek"
        let snippet = SearchSnippet.preview(body: body, taskTexts: [], query: "interceptor")
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.contains("interceptor eklenecek"))
        #expect(!snippet.hasPrefix("…elime"))
    }

    @Test func snippetFallsBackToMatchingTask() {
        let snippet = SearchSnippet.preview(body: "Gövde", taskTexts: ["Süt", "Keychain ile oturum"], query: "keychain")
        #expect(snippet == "☐ Keychain ile oturum")
    }
}
