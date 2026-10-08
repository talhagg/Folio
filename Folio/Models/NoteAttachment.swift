import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Nota eklenen görsel ya da dosya. Not metninde `![ad](attachment:<id>)` (görsel) ya da
/// `[ad](attachment:<id>)` (dosya) olarak geçer. Veri harici depolamada; iCloud'da CKAsset olarak senkronlanır.
@Model
final class NoteAttachment {
    var id: UUID = UUID()
    var fileName: String = ""
    var typeIdentifier: String = ""
    @Attribute(.externalStorage) var data: Data?
    var byteCount: Int = 0
    var createdAt: Date = Date.now
    var note: Note?

    init(fileName: String, typeIdentifier: String, data: Data, createdAt: Date = .now) {
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
        self.data = data
        self.byteCount = data.count
        self.createdAt = createdAt
    }

    var contentType: UTType { UTType(typeIdentifier) ?? .data }
    var isImage: Bool { contentType.conforms(to: .image) }

    static let maxBytes = 25 * 1024 * 1024
    static let scheme = "attachment"

    var reference: String { "\(Self.scheme):\(id.uuidString)" }

    /// Not metnine eklenecek markdown.
    var markdown: String {
        let label = fileName.replacingOccurrences(of: "]", with: ")").replacingOccurrences(of: "[", with: "(")
        return isImage ? "![\(label)](\(reference))" : "[\(label)](\(reference))"
    }

    static func id(fromReference reference: String) -> UUID? {
        guard reference.hasPrefix(scheme + ":") else { return nil }
        return UUID(uuidString: String(reference.dropFirst(scheme.count + 1)))
    }

    /// Görüntülemek/açmak için geçici dosya.
    func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Folio-\(id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName.isEmpty ? "ek" : fileName.replacingOccurrences(of: "/", with: "-")
        let url = directory.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path()) {
            try (data ?? Data()).write(to: url)
        }
        return url
    }
}

enum AttachmentError: LocalizedError {
    case tooLarge(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let name): String(localized: "\(name) çok büyük (en fazla 25 MB).")
        case .unreadable(let name): String(localized: "\(name) okunamadı.")
        }
    }
}

extension ModelContext {
    @discardableResult
    func addAttachment(to note: Note, data: Data, fileName: String, type: UTType, now: Date = .now) throws -> NoteAttachment {
        guard data.count <= NoteAttachment.maxBytes else { throw AttachmentError.tooLarge(fileName) }
        let attachment = NoteAttachment(fileName: fileName, typeIdentifier: type.identifier, data: data, createdAt: now)
        insert(attachment)
        attachment.note = note
        note.touch(now: now)
        return attachment
    }

    func addAttachment(to note: Note, fileURL url: URL, now: Date = .now) throws -> NoteAttachment {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= NoteAttachment.maxBytes else { throw AttachmentError.tooLarge(url.lastPathComponent) }
        guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unreadable(url.lastPathComponent) }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension) ?? .data
        return try addAttachment(to: note, data: data, fileName: url.lastPathComponent, type: type, now: now)
    }

    /// Metinde artık geçmeyen ekleri siler.
    func removeUnreferencedAttachments(of note: Note) {
        let referenced = Set(MarkdownDocument.attachmentIDs(in: note.body))
        for attachment in note.attachments ?? [] where !referenced.contains(attachment.id) {
            attachment.note = nil
            delete(attachment)
        }
    }
}
