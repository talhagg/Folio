import AppKit
import Foundation
import PDFKit
import SwiftData
import Testing
@testable import Folio

@MainActor
struct ExportTests {
    let container = SampleData.container(now: TestClock.now)
    var context: ModelContext { container.mainContext }

    private func sprintNote() throws -> Note {
        try #require(try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.title == "Sprint 42 planlaması" })).first)
    }

    @Test func jsonRoundTripsWithTasks() throws {
        let note = try sprintNote()
        let data = try NoteExporter.data(for: [note], format: .json, now: TestClock.now)
        let export = try FolioExport.decoder.decode(FolioExport.self, from: data)
        #expect(export.app == "Folio")
        #expect(export.notes.first?.tasks.count == 8)
        #expect(export.notes.first?.notebook == "İş")

        let documents = try FileImporter.documents(from: data, fileName: "yedek.json")
        #expect(documents.count == 1)
        #expect(documents[0].title == note.title)
        #expect(documents[0].tasks.count == 8)
        #expect(documents[0].tasks.filter(\.isDone).count == 5)
        #expect(documents[0].isPinned)

        let section = try #require(context.importDocuments(documents, sourceName: "yedek", now: TestClock.now))
        let restored = try #require(section.activeNotes.first)
        #expect(restored.progress == note.progress)
        #expect(restored.body == note.body)
    }

    @Test func markdownHasTitleTasksAndBody() throws {
        let markdown = NoteExporter.markdown(for: try sprintNote())
        #expect(markdown.hasPrefix("# Sprint 42 planlaması\n\n- [x] Login ekranı tasarımı"))
        #expect(markdown.contains("| İş"))
    }

    @Test func docxIsWordDocumentWithTable() throws {
        let data = try NoteExporter.data(for: [try sprintNote()], format: .docx, now: TestClock.now)
        let archive = try ZipArchive(data: data)
        let xml = String(decoding: try #require(try archive.contents(of: "word/document.xml")), as: UTF8.self)
        #expect(xml.contains("Sprint 42 planlaması"))
        #expect(xml.contains("<w:tbl>") || xml.contains("<w:tbl "))
        #expect(xml.contains("Talha"))
        // Word'ün okuyacağı belge Folio'nun kendi içe aktarıcısıyla da açılmalı.
        let reimported = try #require(try DOCXImporter.documents(from: data, fallbackTitle: "x").first)
        #expect(reimported.title == "Sprint 42 planlaması")
        let blocks = MarkdownDocument.parse(reimported.markdown).map(\.block)
        #expect(blocks.contains(.heading(level: 2, text: "Sorumlular")))
        #expect(blocks.contains { if case .table(let table) = $0 { table.header == ["İş", "Sahip", "Durum"] } else { false } })
    }

    @Test func pdfIsPaginatedAndSearchable() throws {
        let data = try NoteExporter.data(for: [try sprintNote()], format: .pdf, now: TestClock.now)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 1)
        let text = document.string ?? ""
        #expect(text.contains("Sprint 42 planlaması"))
        #expect(text.contains("AuthService"))
        #expect(text.contains("Talha"))

        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let page = document.page(at: 0) {
            let image = page.thumbnail(of: NSSize(width: 1190, height: 1684), for: .mediaBox)
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: URL(filePath: directory).appending(path: "export-pdf-page1.png"))
            }
            try data.write(to: URL(filePath: directory).appending(path: "export.pdf"))
            try NoteExporter.data(for: [try sprintNote()], format: .docx, now: TestClock.now)
                .write(to: URL(filePath: directory).appending(path: "export.docx"))
        }
    }

    @Test func zipWriterRoundTripsWithReader() throws {
        let data = ZipWriter.archive([("a/b.txt", Data("merhaba".utf8)), ("c.xml", Data("<x/>".utf8))])
        let archive = try ZipArchive(data: data)
        #expect(try archive.contents(of: "a/b.txt") == Data("merhaba".utf8))
        #expect(try archive.contents(of: "c.xml") == Data("<x/>".utf8))
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func suggestedFileNameIsSafe() {
        let note = Note(title: "Plan: Q4/2026")
        context.insert(note)
        #expect(NoteExporter.suggestedFileName(for: [note], fallback: "Notlar") == "Plan- Q4-2026")
        #expect(NoteExporter.suggestedFileName(for: [], fallback: "Notlar") == "Notlar")
    }
}
