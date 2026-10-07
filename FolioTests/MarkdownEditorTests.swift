import AppKit
import Testing
@testable import Folio

struct LineStyleTests {
    @Test(arguments: [
        ("# Başlık", MarkdownLineStyle.heading1, 2),
        ("## Alt", .heading2, 3),
        ("### Küçük", .heading3, 4),
        ("#### Daha", .heading3, 5),
        ("- madde", .bullet, 2),
        ("- [ ] görev", .task, 6),
        ("* [x] bitti", .task, 6),
        ("12. on iki", .numbered, 4),
        ("> alıntı", .quote, 2),
        ("düz metin", .body, 0),
        ("#etiket", .body, 0),
    ])
    func detects(line: String, style: MarkdownLineStyle, prefix: Int) {
        let detected = MarkdownLineStyle.detect(line)
        #expect(detected.style == style)
        #expect(detected.prefixLength == prefix)
    }
}

@MainActor
struct EditorControllerTests {
    private func make(_ text: String, selection: NSRange) -> (MarkdownEditorController, NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.string = text
        textView.setSelectedRange(selection)
        let controller = MarkdownEditorController()
        controller.attach(textView)
        return (controller, textView)
    }

    @Test func boldWrapsAndUnwrapsSelection() {
        let (controller, textView) = make("merhaba dünya", selection: NSRange(location: 8, length: 5))
        controller.toggleInline("**")
        #expect(textView.string == "merhaba **dünya**")
        #expect(textView.selectedRange() == NSRange(location: 10, length: 5))
        controller.toggleInline("**")
        #expect(textView.string == "merhaba dünya")
    }

    @Test func emptySelectionInsertsMarkersAroundCaret() {
        let (controller, textView) = make("a ", selection: NSRange(location: 2, length: 0))
        controller.toggleInline("`")
        #expect(textView.string == "a ``")
        #expect(textView.selectedRange().location == 3)
    }

    @Test func pressingAgainOnEmptyPairRemovesIt() {
        let (controller, textView) = make("a ", selection: NSRange(location: 2, length: 0))
        controller.toggleInline("**")
        controller.toggleInline("**")
        #expect(textView.string == "a ")
        #expect(textView.selectedRange().location == 2)
    }

    @Test func caretInsideWordBoldsTheWord() {
        let (controller, textView) = make("merhaba dünya", selection: NSRange(location: 3, length: 0))
        controller.toggleInline("**")
        #expect(textView.string == "**merhaba** dünya")
        #expect(textView.selectedRange().location == 5)
    }

    @Test func caretAtEndOfBoldSpanExitsIt() {
        let (controller, textView) = make("**kalın** sonra", selection: NSRange(location: 7, length: 0))
        controller.toggleInline("**")
        #expect(textView.string == "**kalın** sonra")
        #expect(textView.selectedRange().location == 9)
    }

    @Test func caretInsideBoldSpanUnbolds() {
        let (controller, textView) = make("x **kalın** y", selection: NSRange(location: 6, length: 0))
        controller.toggleInline("**")
        #expect(textView.string == "x kalın y")
    }

    @Test func selectionIncludingMarkersUnwraps() {
        let (controller, textView) = make("x *italik* y", selection: NSRange(location: 2, length: 8))
        controller.toggleInline("*")
        #expect(textView.string == "x italik y")
    }

    @Test func headingReplacesListPrefixAndToggles() {
        let (controller, textView) = make("- satır\nikinci", selection: NSRange(location: 3, length: 0))
        controller.setLineStyle(.heading2)
        #expect(textView.string == "## satır\nikinci")
        controller.setLineStyle(.heading2)
        #expect(textView.string == "satır\nikinci")
    }

    @Test func numberedListNumbersEachSelectedLine() {
        let (controller, textView) = make("bir\niki\nüç", selection: NSRange(location: 0, length: 9))
        controller.setLineStyle(.numbered)
        #expect(textView.string == "1. bir\n2. iki\n3. üç")
    }

    @Test func insertBlockAddsBlankLinesAroundAtCaret() {
        let (controller, textView) = make("Önce\nSonra", selection: NSRange(location: 4, length: 0))
        controller.insertBlock("| a |\n| --- |")
        #expect(textView.string == "Önce\n\n| a |\n| --- |\n\nSonra")
    }
}

@MainActor
struct ListContinuationTests {
    private func editor(_ text: String, caret: Int) -> (MarkdownTextEditor.Coordinator, NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let controller = MarkdownEditorController()
        controller.attach(textView)
        let coordinator = MarkdownTextEditor(text: .constant(text), scale: 1, controller: controller).makeCoordinator()
        return (coordinator, textView)
    }

    @Test func returnContinuesNumbering() {
        let (coordinator, textView) = editor("1. bir", caret: 6)
        #expect(coordinator.continueList(textView))
        #expect(textView.string == "1. bir\n2. ")
        textView.insertText("iki", replacementRange: textView.selectedRange())
        #expect(coordinator.continueList(textView))
        #expect(textView.string == "1. bir\n2. iki\n3. ")
    }

    @Test func returnOnEmptyItemEndsList() {
        let (coordinator, textView) = editor("- a\n- ", caret: 6)
        #expect(coordinator.continueList(textView))
        #expect(textView.string == "- a\n")
    }

    @Test func plainLineIsNotHandled() {
        let (coordinator, textView) = editor("metin", caret: 5)
        #expect(!coordinator.continueList(textView))
    }

    @Test func numberingContinuesFromLineAbove() {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.string = "1. bir\n2. iki\nüç"
        textView.setSelectedRange(NSRange(location: 15, length: 0))
        let controller = MarkdownEditorController()
        controller.attach(textView)
        controller.setLineStyle(.numbered)
        #expect(textView.string == "1. bir\n2. iki\n3. üç")
    }

    @Test func numberedOnEmptyLineInsertsPrefix() {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.string = "Liste:\n"
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        let controller = MarkdownEditorController()
        controller.attach(textView)
        controller.setLineStyle(.numbered)
        #expect(textView.string == "Liste:\n1. ")
        #expect(textView.selectedRange().location == 10)
    }
}

/// Biçim işaretleri editörde görünmemeli (boş çiftler dahil).
@MainActor
struct HiddenMarkerTests {
    private func styled(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler.style(storage, scale: 1)
        return storage
    }

    private func isHidden(_ storage: NSTextStorage, at index: Int) -> Bool {
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
        return (font?.pointSize ?? 99) < 1 && color == .clear
    }

    @Test func spanMarkersAreHidden() {
        let storage = styled("a **kalın** b")
        #expect(isHidden(storage, at: 2) && isHidden(storage, at: 3))
        #expect(isHidden(storage, at: 9) && isHidden(storage, at: 10))
        #expect(!isHidden(storage, at: 4))
    }

    @Test(arguments: ["a ****", "a **", "a ``", "**** b", "a ******** b"])
    func emptyPairsAreHidden(text: String) {
        let storage = styled(text)
        let markers = (text as NSString).length
        for index in 0..<markers where "*`".contains((text as NSString).substring(with: NSRange(location: index, length: 1))) {
            #expect(isHidden(storage, at: index), "index \(index) in \(text)")
        }
    }

    @Test func listMarkerStaysVisible() {
        #expect(!isHidden(styled("- madde"), at: 0))
        #expect(!isHidden(styled("* madde"), at: 0))
    }

    @Test func ruleAndArithmeticStayVisible() {
        #expect(!isHidden(styled("***"), at: 0))
        #expect(!isHidden(styled("5 * 3"), at: 2))
    }
}

@MainActor
struct TypingFlowTests {
    @Test func typeThenBoldThenTypeShowsBoldWithoutStars() throws {
        let controller = MarkdownEditorController()
        let editor = MarkdownTextEditor(text: .constant(""), scale: 1, controller: controller)
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.isRichText = false
        textView.delegate = coordinator
        controller.attach(textView)

        textView.insertText("Merhaba ", replacementRange: textView.selectedRange())
        controller.toggleInline("**")
        textView.insertText("dünya", replacementRange: textView.selectedRange())
        controller.toggleInline("**")   // kalından çık
        textView.insertText(" sonra", replacementRange: textView.selectedRange())

        #expect(textView.string == "Merhaba **dünya** sonra")
        let storage = try #require(textView.textStorage)
        let boldFont = try #require(storage.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        let marker = try #require(storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
        #expect(marker.pointSize < 1)
        let after = try #require(storage.attribute(.font, at: 19, effectiveRange: nil) as? NSFont)
        #expect(!after.fontDescriptor.symbolicTraits.contains(.bold))
    }
}
