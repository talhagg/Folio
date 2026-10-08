import Compression
import Foundation
import SwiftData
import Testing
@testable import Folio

struct CSVAndTabularTests {
    @Test func parsesQuotesNewlinesAndSemicolons() {
        let csv = "\u{FEFF}Başlık;Açıklama\n\"Toplantı; ekip\";\"İki\nsatır, \"\"alıntı\"\"\"\r\nSon;x"
        let rows = CSVParser.parse(csv)
        #expect(rows == [["Başlık", "Açıklama"], ["Toplantı; ekip", "İki\nsatır, \"alıntı\""], ["Son", "x"]])
    }

    @Test func rowsBecomeNotesWhenTitleColumnExists() {
        let docs = CSVParser.documents(from: "Konu,İçerik,Sahip,Tarih\nA,Gövde A,Ali,2026-10-01\nB,,Ayşe,\n,,,\n", fallbackTitle: "dosya")
        #expect(docs.map(\.title) == ["A", "B"])
        #expect(docs[0].markdown == "Gövde A\n\n- **Sahip:** Ali")
        #expect(docs[1].markdown == "- **Sahip:** Ayşe")
        #expect(docs[0].createdAt != nil)
    }

    @Test func otherwiseSingleNoteWithTable() {
        let docs = CSVParser.documents(from: "Ürün,Fiyat\nKalem,5\nDefter,12", fallbackTitle: "fiyatlar")
        #expect(docs.count == 1)
        #expect(docs[0].title == "fiyatlar")
        #expect(MarkdownDocument.parse(docs[0].markdown).map(\.block) == [
            .table(MarkdownTable(header: ["Ürün", "Fiyat"], rows: [["Kalem", "5"], ["Defter", "12"]])),
        ])
    }

    @Test func parsesCommonDateFormats() {
        #expect(DateParsing.parse("2026-10-07") != nil)
        #expect(DateParsing.parse("07.10.2026") != nil)
        #expect(DateParsing.parse("2026-10-07T14:32:00Z") != nil)
        #expect(DateParsing.parse("dün") == nil)
    }
}

struct JSONImportTests {
    private func docs(_ json: String) throws -> [ImportedDocument] {
        try JSONImporter.documents(from: Data(json.utf8), fallbackTitle: "veri")
    }

    @Test func arrayOfNotes() throws {
        let result = try docs(#"[{"title":"Bir","body":"Metin","tags":["a","b"]},{"title":"İki","body":"x"}]"#)
        #expect(result.map(\.title) == ["Bir", "İki"])
        #expect(result[0].markdown == "Metin\n\n- **tags:** [\"a\",\"b\"]")
    }

    @Test func nestedContainerKey() throws {
        #expect(try docs(#"{"version":1,"notes":[{"başlık":"Not","içerik":"Gövde"}]}"#).map(\.title) == ["Not"])
    }

    @Test func singleObjectWithTitle() throws {
        let result = try docs(#"{"title":"Tek","content":"Gövde"}"#)
        #expect(result == [ImportedDocument(title: "Tek", markdown: "Gövde")])
    }

    @Test func unknownShapeBecomesCodeBlock() throws {
        let result = try docs(#"{"a":{"b":1}}"#)
        #expect(result.count == 1)
        #expect(result[0].markdown.hasPrefix("```json"))
    }

    @Test func invalidJSONThrows() {
        #expect(throws: ImportError.self) { try docs("{nope") }
    }
}

struct HTMLImportTests {
    @Test func convertsWebPage() {
        let html = """
        <html><head><title>Sayfa</title><script>alert(1)</script></head>
        <body><nav>menü</nav><article>
        <h1>Başlık</h1><p>Bir <strong>kalın</strong> ve <a href="https://ornek.com">bağlantı</a>.</p>
        <ul><li>bir</li><li>iki<ul><li>alt</li></ul></li></ul>
        <table><tr><th>Ad</th><th>Puan</th></tr><tr><td>Ali</td><td>3</td></tr></table>
        <pre>let x = 1</pre>
        </article></body></html>
        """
        let result = HTMLToMarkdown.convert(html: html)
        #expect(result.title == "Sayfa")
        #expect(!result.markdown.contains("alert"))
        #expect(!result.markdown.contains("menü"))
        #expect(result.markdown.contains("# Başlık"))
        #expect(result.markdown.contains("Bir **kalın** ve [bağlantı](https://ornek.com)."))
        #expect(result.markdown.contains("- bir\n- iki\n  - alt"))
        #expect(result.markdown.contains("```\nlet x = 1\n```"))
        let tables = MarkdownDocument.parse(result.markdown).compactMap { if case .table(let t) = $0.block { t } else { nil } }
        #expect(tables == [MarkdownTable(header: ["Ad", "Puan"], rows: [["Ali", "3"]])])
    }

    @Test func convertsConfluenceStorage() {
        let storage = """
        <h2>Plan</h2><p>Bu hafta&nbsp;yapılacaklar &ndash; özet</p>
        <ac:task-list><ac:task><ac:task-status>complete</ac:task-status><ac:task-body>Tasarım</ac:task-body></ac:task>
        <ac:task><ac:task-status>incomplete</ac:task-status><ac:task-body>API</ac:task-body></ac:task></ac:task-list>
        <ac:structured-macro ac:name="code"><ac:parameter ac:name="language">swift</ac:parameter>
        <ac:plain-text-body><![CDATA[let a = 1 < 2]]></ac:plain-text-body></ac:structured-macro>
        <ac:structured-macro ac:name="info"><ac:rich-text-body><p>Not önemli</p></ac:rich-text-body></ac:structured-macro>
        <table><tbody><tr><th>Kim</th><th>Ne</th></tr><tr><td><p>Ali</p></td><td>Test</td></tr></tbody></table>
        <p><ac:link><ri:page ri:content-title="Diğer Sayfa" /></ac:link></p>
        """
        let markdown = HTMLToMarkdown.convert(confluenceStorage: storage)
        #expect(markdown.contains("## Plan"))
        #expect(markdown.contains("Bu hafta yapılacaklar – özet"))
        #expect(markdown.contains("- [x] Tasarım\n- [ ] API"))
        #expect(markdown.contains("```swift\nlet a = 1 < 2\n```"))
        #expect(markdown.contains("> Not önemli"))
        #expect(markdown.contains("| Kim"))
        #expect(markdown.contains("Diğer Sayfa"))
    }
}

/// Testler için en küçük ZIP yazıcı (deflate).
private enum TestZip {
    static func make(_ files: [(String, String)]) -> Data {
        var archive: [UInt8] = []
        var central: [UInt8] = []
        for (name, content) in files {
            let raw = [UInt8](content.utf8)
            var compressed = [UInt8](repeating: 0, count: raw.count + 1024)
            let size = compression_encode_buffer(&compressed, compressed.count, raw, raw.count, nil, COMPRESSION_ZLIB)
            let body = Array(compressed.prefix(size))
            let nameBytes = [UInt8](name.utf8)
            let offset = UInt32(archive.count)

            var local: [UInt8] = []
            put32(&local, 0x0403_4B50)
            for value: UInt16 in [20, 0, 8, 0, 0] { put16(&local, value) }
            put32(&local, 0)
            put32(&local, UInt32(body.count))
            put32(&local, UInt32(raw.count))
            put16(&local, UInt16(nameBytes.count))
            put16(&local, 0)
            archive += local
            archive += nameBytes
            archive += body

            var entry: [UInt8] = []
            put32(&entry, 0x0201_4B50)
            for value: UInt16 in [20, 20, 0, 8, 0, 0] { put16(&entry, value) }
            put32(&entry, 0)
            put32(&entry, UInt32(body.count))
            put32(&entry, UInt32(raw.count))
            put16(&entry, UInt16(nameBytes.count))
            for value: UInt16 in [0, 0, 0, 0] { put16(&entry, value) }
            put32(&entry, 0)
            put32(&entry, offset)
            central += entry
            central += nameBytes
        }
        let centralOffset = UInt32(archive.count)
        archive += central
        var end: [UInt8] = []
        put32(&end, 0x0605_4B50)
        for value: UInt16 in [0, 0, UInt16(files.count), UInt16(files.count)] { put16(&end, value) }
        put32(&end, UInt32(central.count))
        put32(&end, centralOffset)
        put16(&end, 0)
        archive += end
        return Data(archive)
    }

    private static func put16(_ bytes: inout [UInt8], _ value: UInt16) {
        bytes += [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func put32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes += [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
}

struct OfficeImportTests {
    @Test func zipRoundTrip() throws {
        let zip = try ZipArchive(data: TestZip.make([("a.txt", String(repeating: "merhaba ", count: 200))]))
        let data = try #require(try zip.contents(of: "a.txt"))
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("merhaba merhaba"))
        #expect(try zip.contents(of: "yok.txt") == nil)
    }

    @Test func rejectsNonZip() {
        #expect(throws: ImportError.self) { try ZipArchive(data: Data("not a zip".utf8)) }
    }

    @Test func importsXLSX() throws {
        let ns = #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships""#
        let data = TestZip.make([
            ("xl/workbook.xml", "<workbook \(ns)><sheets><sheet name=\"Görevler\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#),
            ("xl/sharedStrings.xml", "<sst \(ns)><si><t>Başlık</t></si><si><t>Durum</t></si><si><r><t>Rapor </t></r><r><t>yaz</t></r></si></sst>"),
            ("xl/worksheets/sheet1.xml", """
            <worksheet \(ns)><sheetData>
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
            <row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>42</v></c></row>
            <row r="3"><c r="A3" t="inlineStr"><is><t>Satır içi</t></is></c><c r="B3" t="b"><v>1</v></c></row>
            </sheetData></worksheet>
            """),
        ])
        let docs = try XLSXImporter.documents(from: data, fallbackTitle: "tablo")
        #expect(docs.map(\.title) == ["Rapor yaz", "Satır içi"])
        #expect(docs[1].markdown == "- **Durum:** TRUE")
    }

    @Test func columnIndexFromReference() {
        #expect(XLSXImporter.columnIndex("A1") == 0)
        #expect(XLSXImporter.columnIndex("Z9") == 25)
        #expect(XLSXImporter.columnIndex("AB12") == 27)
        #expect(XLSXImporter.columnIndex("12") == nil)
    }

    @Test func importsDOCX() throws {
        let w = #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""#
        let data = TestZip.make([
            ("word/document.xml", """
            <w:document \(w)><w:body>
            <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t>Toplantı Notu</w:t></w:r></w:p>
            <w:p><w:r><w:t xml:space="preserve">Karar: </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>yayın</w:t></w:r></w:p>
            <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Maddeler</w:t></w:r></w:p>
            <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr><w:r><w:t>bir</w:t></w:r></w:p>
            <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr><w:r><w:t>iki</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Ad</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Rol</w:t></w:r></w:p></w:tc></w:tr>
            <w:tr><w:tc><w:p><w:r><w:t>Ali</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Lider</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            </w:body></w:document>
            """),
        ])
        let docs = try DOCXImporter.documents(from: data, fallbackTitle: "belge")
        #expect(docs.count == 1)
        #expect(docs[0].title == "Toplantı Notu")
        let blocks = MarkdownDocument.parse(docs[0].markdown).map(\.block)
        #expect(blocks == [
            .paragraph("Karar: **yayın**"),
            .heading(level: 2, text: "Maddeler"),
            .bulletList([.init(text: "bir"), .init(text: "iki")]),
            .table(MarkdownTable(header: ["Ad", "Rol"], rows: [["Ali", "Lider"]])),
        ])
    }

    @Test func dispatchesByExtension() throws {
        #expect(try FileImporter.documents(from: Data("# Başlık\nGövde".utf8), fileName: "not.md")
            == [ImportedDocument(title: "Başlık", markdown: "Gövde")])
        #expect(throws: ImportError.unsupportedFormat("xls")) {
            try FileImporter.documents(from: Data(), fileName: "eski.xls")
        }
    }
}

@MainActor
struct ImportIntoLibraryTests {
    @Test func createsImportNotebookAndUniqueSections() throws {
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let docs = [ImportedDocument(title: "A", markdown: "a"), ImportedDocument(title: "B", markdown: "b", createdAt: TestClock.now)]
        let first = try #require(context.importDocuments(docs, sourceName: "rapor.csv", now: TestClock.now))
        let second = try #require(context.importDocuments(docs, sourceName: "rapor.csv", now: TestClock.now))
        #expect(first.notebook?.name == "İçe Aktarılanlar")
        #expect(first.notebook === second.notebook)
        #expect(second.name == "rapor.csv (2)")
        #expect(first.activeNotes.map(\.title).sorted() == ["A", "B"])
        #expect(try context.fetchCount(FetchDescriptor<Notebook>()) == 1)
    }
}

struct URLImportTests {
    @Test func parsesConfluenceCloudLinks() throws {
        let link = try #require(ConfluenceLink.parse(URL(string: "https://sirket.atlassian.net/wiki/spaces/ENG/pages/123456/Sprint+Plan")!))
        #expect(link.deployment == .cloud)
        #expect(link.pageID == "123456")
        #expect(link.baseURL.absoluteString == "https://sirket.atlassian.net/wiki")
        #expect(ConfluenceLink.parse(URL(string: "https://sirket.atlassian.net/wiki/spaces/ENG/pages/edit-v2/987")!)?.pageID == "987")
    }

    @Test func parsesConfluenceServerLinks() throws {
        let viewPage = try #require(ConfluenceLink.parse(URL(string: "https://wiki.sirket.com/confluence/pages/viewpage.action?pageId=42")!))
        #expect(viewPage.deployment == .server)
        #expect(viewPage.pageID == "42")
        #expect(viewPage.baseURL.absoluteString == "https://wiki.sirket.com/confluence")
        let dataCenter = try #require(ConfluenceLink.parse(URL(string: "https://wiki.sirket.com/spaces/OPS/pages/77/Runbook")!))
        #expect(dataCenter.baseURL.absoluteString == "https://wiki.sirket.com")
    }

    @Test func ordinaryURLsAreNotConfluence() {
        #expect(ConfluenceLink.parse(URL(string: "https://ornek.com/blog/pages/12")!) == nil)
        #expect(ConfluenceLink.parse(URL(string: "https://ornek.com/yazi")!) == nil)
    }

    @Test func validatesURLs() {
        #expect(URLImporter.validatedURL("ornek.com/sayfa")?.absoluteString == "https://ornek.com/sayfa")
        #expect(URLImporter.validatedURL("file:///etc/passwd") == nil)
        #expect(URLImporter.validatedURL("javascript:alert(1)") == nil)
        #expect(URLImporter.validatedURL("   ") == nil)
    }

    @Test func credentialsOnlyApplyToTheirSite() {
        let credentials = ConfluenceCredentials(site: "https://sirket.atlassian.net/wiki", email: "a@b.com", token: "t")
        #expect(credentials.host == "sirket.atlassian.net")
        #expect(credentials.applies(to: URL(string: "https://sirket.atlassian.net/wiki/api/v2/pages/1")!))
        #expect(!credentials.applies(to: URL(string: "https://kotu.example.com/wiki")!))
        #expect(credentials.authorizationHeader() == "Basic " + Data("a@b.com:t".utf8).base64EncodedString())
        #expect(ConfluenceCredentials(site: "wiki.sirket.com", email: "", token: "pat").authorizationHeader() == "Bearer pat")
    }
}

struct WebPageTitleTests {
    @Test func cleansConfluenceTitles() {
        #expect(WebPage.cleanTitle("Sprint Plan - Mühendislik - Confluence") == "Sprint Plan")
        #expect(WebPage.cleanTitle("Örnek Sayfa") == "Örnek Sayfa")
        #expect(WebPage.cleanTitle("  ") == nil)
    }
}
