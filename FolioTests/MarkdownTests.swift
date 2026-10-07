import Testing
@testable import Folio

struct MarkdownTests {
    @Test func parsesBlocksWithLineRanges() {
        let text = """
        # Başlık

        Paragraf **kalın**
        ikinci satır

        - [x] bitti
        - [ ] kaldı
        - düz madde

        1. bir
        2. iki

        > alıntı

        ```swift
        let a = 1
        ```

        | Ad | Puan |
        | --- | ---: |
        | Ali | 3 |
        | Ayşe \\| Can | 5 |

        ---
        """
        let blocks = MarkdownDocument.parse(text)
        #expect(blocks.map(\.block) == [
            .heading(level: 1, text: "Başlık"),
            .paragraph("Paragraf **kalın**\nikinci satır"),
            .bulletList([.init(text: "bitti", isChecked: true), .init(text: "kaldı", isChecked: false), .init(text: "düz madde", isChecked: nil)]),
            .orderedList(["bir", "iki"]),
            .quote("alıntı"),
            .code(language: "swift", text: "let a = 1"),
            .table(MarkdownTable(header: ["Ad", "Puan"], rows: [["Ali", "3"], ["Ayşe | Can", "5"]])),
            .rule,
        ])
        let table = blocks.first { if case .table = $0.block { true } else { false } }
        #expect(table?.lines == 18..<22)
    }

    @Test func paragraphStopsAtTable() {
        let blocks = MarkdownDocument.parse("Metin\n| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(blocks.count == 2)
        #expect(blocks[0].block == .paragraph("Metin"))
    }

    @Test func tableRoundTripsThroughMarkdown() {
        let table = MarkdownTable(header: ["Ad", "Not"], rows: [["Ali", "a|b"], ["Ayşe"]])
        let parsed = MarkdownDocument.parse(table.markdown)
        #expect(parsed.map(\.block) == [.table(MarkdownTable(header: ["Ad", "Not"], rows: [["Ali", "a|b"], ["Ayşe", ""]]))])
    }

    @Test func replacingLinesSwapsOnlyTheRange() {
        let text = "a\nb\nc\nd"
        #expect(MarkdownDocument.replacingLines(1..<3, in: text, with: "X\nY\nZ") == "a\nX\nY\nZ\nd")
    }

    @Test func appendingBlockSeparatesWithBlankLine() {
        #expect(MarkdownDocument.appendingBlock("| a |", to: "Metin\n\n") == "Metin\n\n| a |\n")
        #expect(MarkdownDocument.appendingBlock("| a |", to: "") == "| a |\n")
    }

    @Test func emptyTableHasRequestedShape() {
        let table = MarkdownTable.empty(columns: 3, rows: 2)
        #expect(table.header.count == 3)
        #expect(table.rows.count == 2)
        #expect(table.rows.allSatisfy { $0.count == 3 })
    }
}
