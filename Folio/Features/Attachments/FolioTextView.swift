import AppKit
import UniformTypeIdentifiers

/// Ek kabul eden metin görünümü: dosya/görsel yapıştırma ve sürükle-bırak eke dönüşür,
/// eklerin markdown'ı imlecin yerine yazılır. Düz metin yapıştırma etkilenmez.
final class FolioTextView: NSTextView {
    /// Eki oluşturur ve metne yazılacak markdown'ı döndürür (hata olursa `nil`).
    var onAttach: ((AttachmentInput) -> String?)?

    override func paste(_ sender: Any?) {
        if onAttach != nil {
            let inputs = Self.attachments(from: .general)
            if !inputs.isEmpty, insert(inputs) { return }
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onAttach != nil, !Self.attachments(from: sender.draggingPasteboard, filesOnly: true).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let inputs = onAttach == nil ? [] : Self.attachments(from: sender.draggingPasteboard, filesOnly: true)
        guard !inputs.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        return insert(inputs)
    }

    private func insert(_ inputs: [AttachmentInput]) -> Bool {
        let markdown = inputs.compactMap { onAttach?($0) }
        guard !markdown.isEmpty else { return false }
        let text = string as NSString
        let location = selectedRange().location
        let needsLeadingBreak = location > 0 && text.character(at: location - 1) != 0x0A
        insertText((needsLeadingBreak ? "\n" : "") + markdown.joined(separator: "\n") + "\n", replacementRange: selectedRange())
        return true
    }

    /// Panodaki ekler: önce dosyalar; metin varsa metin tercih edilir; yoksa görsel verisi.
    static func attachments(from pasteboard: NSPasteboard, filesOnly: Bool = false) -> [AttachmentInput] {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { return urls.map { .file($0) } }
        guard !filesOnly, pasteboard.string(forType: .string) == nil else { return [] }
        if let png = pasteboard.data(forType: .png) { return [.image(png, .png)] }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return [.image(png, .png)]
        }
        return []
    }
}
