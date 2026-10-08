import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Folio

@MainActor
struct AttachmentTests {
    let container = ModelContainer.folioInMemory()
    var context: ModelContext { container.mainContext }

    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func parsesImageAndAttachmentBlocks() {
        let id = UUID()
        let text = "Önce\n![foto](attachment:\(id.uuidString))\n[rapor.pdf](attachment:\(id.uuidString))\n![web](https://ornek.com/a.png)\nSonra"
        let blocks = MarkdownDocument.parse(text).map(\.block)
        #expect(blocks == [
            .paragraph("Önce"),
            .image(alt: "foto", source: "attachment:\(id.uuidString)"),
            .attachment(name: "rapor.pdf", source: "attachment:\(id.uuidString)"),
            .image(alt: "web", source: "https://ornek.com/a.png"),
            .paragraph("Sonra"),
        ])
        #expect(MarkdownDocument.attachmentIDs(in: text) == [id, id])
    }

    @Test func addsAttachmentAndBuildsMarkdown() throws {
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: "n")
        let image = try context.addAttachment(to: note, data: pngData(), fileName: "foto.png", type: .png)
        let file = try context.addAttachment(to: note, data: Data("pdf".utf8), fileName: "rapor.pdf", type: .pdf)
        #expect(image.isImage && !file.isImage)
        #expect(image.markdown == "![foto.png](attachment:\(image.id.uuidString))")
        #expect(file.markdown == "[rapor.pdf](attachment:\(file.id.uuidString))")
        #expect(note.attachment(image.id) === image)
        #expect(NoteAttachment.id(fromReference: image.reference) == image.id)
    }

    @Test func rejectsTooLargeFiles() {
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: "n")
        #expect(throws: AttachmentError.self) {
            try context.addAttachment(to: note, data: Data(count: NoteAttachment.maxBytes + 1), fileName: "büyük.bin", type: .data)
        }
    }

    @Test func removesUnreferencedAttachments() throws {
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: "n")
        let kept = try context.addAttachment(to: note, data: Data("a".utf8), fileName: "a.txt", type: .plainText)
        _ = try context.addAttachment(to: note, data: Data("b".utf8), fileName: "b.txt", type: .plainText)
        note.body = "Metin\n" + kept.markdown
        context.removeUnreferencedAttachments(of: note)
        #expect(note.attachments?.map(\.fileName) == ["a.txt"])
    }

    @Test func pasteboardPrefersFilesThenTextThenImage() throws {
        let board = NSPasteboard(name: .init("folio.test.\(UUID().uuidString)"))
        board.clearContents()
        board.setData(pngData(), forType: .png)
        guard case .image(_, let type)? = FolioTextView.attachments(from: board).first else {
            Issue.record("görsel bekleniyordu"); return
        }
        #expect(type == .png)

        board.clearContents()
        board.setString("düz metin", forType: .string)
        board.setData(pngData(), forType: .png)
        #expect(FolioTextView.attachments(from: board).isEmpty)

        board.clearContents()
        let url = FileManager.default.temporaryDirectory.appending(path: "ek-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        board.writeObjects([url as NSURL])
        guard case .file(let found)? = FolioTextView.attachments(from: board).first else {
            Issue.record("dosya bekleniyordu"); return
        }
        #expect(found.lastPathComponent == url.lastPathComponent)
        board.releaseGlobally()
    }

    @Test func exportsHandleAttachments() throws {
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: "Ekli")
        let image = try context.addAttachment(to: note, data: pngData(), fileName: "foto.png", type: .png)
        let file = try context.addAttachment(to: note, data: Data("x".utf8), fileName: "rapor.pdf", type: .pdf)
        note.body = "Giriş\n\(image.markdown)\n\(file.markdown)"
        let markdown = NoteExporter.markdown(for: note)
        #expect(markdown.contains("[Görsel: foto.png]") && markdown.contains("[Ek: rapor.pdf]"))
        #expect(!markdown.contains("attachment:"))
        let pdf = try NoteExporter.data(for: [note], format: .pdf)
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        let docx = try NoteExporter.data(for: [note], format: .docx)
        let xml = String(decoding: try #require(try ZipArchive(data: docx).contents(of: "word/document.xml")), as: UTF8.self)
        #expect(xml.contains("rapor.pdf"))
    }
}

@MainActor
struct AttachmentSnapshotTests {
    @Test(arguments: [false, true])
    func previewAndEditing(editing: Bool) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let container = ModelContainer.folioInMemory()
        let context = container.mainContext
        let note = context.addNote(in: context.sectionForNewNote(selection: nil), title: "Tasarım incelemesi")
        let image = NSImage(size: NSSize(width: 520, height: 220), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemBlue])!.draw(in: rect, angle: 0)
            ("Ekran tasarımı" as NSString).draw(at: NSPoint(x: 24, y: 90), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 34), .foregroundColor: NSColor.white])
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let shot = try context.addAttachment(to: note, data: png, fileName: "giris-ekrani.png", type: .png)
        let pdf = try context.addAttachment(to: note, data: Data("%PDF-1.4".utf8), fileName: "gereksinimler.pdf", type: .pdf)
        note.body = "Yeni giriş ekranı aşağıda.\n\n\(shot.markdown)\n\n\(pdf.markdown)\n\nYorumlar #tasarım"
        let view = NavigationStack { NoteEditorView(note: note, startsEditingBody: editing) }.modelContainer(container)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)); hosting.layoutSubtreeIfNeeded() }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: URL(filePath: directory).appending(path: "attachments-\(editing ? "editing" : "preview").png"))
    }
}
