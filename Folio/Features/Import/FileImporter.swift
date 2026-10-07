import Foundation
import UniformTypeIdentifiers

/// Dosya uzantısına göre doğru dönüştürücüyü seçer.
enum FileImporter {
    static let maxFileSize = 50 * 1024 * 1024

    static let supportedTypes: [UTType] = [
        .commaSeparatedText, .tabSeparatedText, .json, .plainText, .html,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
    ]

    static func documents(from url: URL) throws -> [ImportedDocument] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileSize else { throw ImportError.tooLarge }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        return try documents(from: data, fileName: url.lastPathComponent)
    }

    static func documents(from data: Data, fileName: String) throws -> [ImportedDocument] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let title = (fileName as NSString).deletingPathExtension
        let documents: [ImportedDocument]
        switch ext {
        case "csv", "tsv":
            guard let text = TextDecoding.string(from: data) else { throw ImportError.unreadable("metin kodlaması tanınmadı") }
            documents = ext == "tsv"
                ? TabularImport.documents(from: CSVParser.parse(text, delimiter: "\t"), fallbackTitle: title)
                : CSVParser.documents(from: text, fallbackTitle: title)
        case "json":
            documents = try JSONImporter.documents(from: data, fallbackTitle: title)
        case "xlsx":
            documents = try XLSXImporter.documents(from: data, fallbackTitle: title)
        case "docx":
            documents = try DOCXImporter.documents(from: data, fallbackTitle: title)
        case "md", "markdown", "txt", "text":
            guard let text = TextDecoding.string(from: data) else { throw ImportError.unreadable("metin kodlaması tanınmadı") }
            documents = [MarkdownImporter.document(from: text, fallbackTitle: title)]
        case "html", "htm":
            guard let text = TextDecoding.string(from: data) else { throw ImportError.unreadable("metin kodlaması tanınmadı") }
            let result = HTMLToMarkdown.convert(html: text)
            documents = [ImportedDocument(title: result.title ?? title, markdown: result.markdown)]
        default:
            throw ImportError.unsupportedFormat(ext)
        }
        guard !documents.isEmpty else { throw ImportError.empty }
        return documents
    }
}

extension TabularImport {
    static func documents(from rows: [[String]], fallbackTitle: String) -> [ImportedDocument] {
        guard let header = rows.first else { return [] }
        return documents(header: header, rows: Array(rows.dropFirst()), fallbackTitle: fallbackTitle)
    }
}

enum MarkdownImporter {
    /// İlk `# Başlık` satırı not başlığı olur ve gövdeden çıkarılır.
    static func document(from text: String, fallbackTitle: String) -> ImportedDocument {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           let match = lines[index].wholeMatch(of: /#\s+(.+)/) {
            let title = String(match.1).trimmingCharacters(in: .whitespaces)
            lines.remove(at: index)
            return ImportedDocument(title: title, markdown: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ImportedDocument(title: fallbackTitle, markdown: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
