import Foundation
import SwiftData
import Testing
@testable import Folio

struct NoteLinkTests {
    @Test func extractsTagsButNotHeadingsCodeOrURLs() {
        let text = """
        # Başlık
        Bugün #İş ve #fikir/yeni konuştuk, #iş tekrar.
        Sayı #1 değil, adres https://ornek.com/#bolum değil, renk&#123; değil.
        `#kod` değil
        ```
        #blok değil
        ```
        """
        #expect(NoteLinkSyntax.tags(in: text) == ["iş", "fikir/yeni"])
    }

    @Test func extractsWikiLinks() {
        #expect(NoteLinkSyntax.linkedTitles(in: "Bak [[Sprint 42]] ve [[ Bütçe ]]; `[[kod]]`") == ["Sprint 42", "Bütçe"])
    }

    @Test func displayMarkdownMakesLinks() {
        let display = NoteLinkSyntax.displayMarkdown("Bak [[Sprint 42]] #iş")
        #expect(display == "Bak [Sprint 42](folio://title/Sprint%2042) [#iş](folio://tag/i%C5%9F)")
    }

    @Test func plainDropsBrackets() {
        #expect(NoteLinkSyntax.plain("Bak [[Sprint 42]] ve `[[x]]`") == "Bak Sprint 42 ve `[[x]]`")
    }

    @Test(arguments: [AppLink.note(UUID()), .noteTitle("Sprint 42 / Plan"), .tag("iş")])
    func appLinkRoundTrips(link: AppLink) {
        #expect(AppLink(url: link.url) == link)
    }

    @Test func rejectsForeignURLs() {
        #expect(AppLink(url: URL(string: "https://ornek.com/note/x")!) == nil)
        #expect(AppLink(url: URL(string: "folio://note/not-a-uuid")!) == nil)
    }

    @MainActor
    @Test func backlinksAndTagSelection() {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let section = context.sectionForNewNote(selection: nil)
        let target = context.addNote(in: section, title: "Sprint 42")
        let linking = context.addNote(in: section, title: "Retro")
        linking.body = "Bkz. [[sprint 42]] #retro"
        let other = context.addNote(in: section, title: "Diğer")
        other.body = "[[Başka]]"
        #expect(NoteLinkSyntax.backlinks(to: "Sprint 42", in: [target, linking, other], excluding: target.id).map(\.id) == [linking.id])
        #expect(SidebarSelection.tag("retro").includes(linking, now: .now))
        #expect(!SidebarSelection.tag("retro").includes(other, now: .now))
    }
}
