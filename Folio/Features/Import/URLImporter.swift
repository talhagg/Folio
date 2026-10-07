import Foundation

/// Confluence sayfa bağlantısı.
struct ConfluenceLink: Equatable, Sendable {
    enum Deployment: Equatable, Sendable { case cloud, server }

    let deployment: Deployment
    let baseURL: URL
    let pageID: String

    /// Cloud: `https://x.atlassian.net/wiki/spaces/KEY/pages/123/Baslik`
    /// Server/DC: `…/pages/viewpage.action?pageId=123` ya da `…/spaces/KEY/pages/123/…`
    static func parse(_ url: URL) -> ConfluenceLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme, let host = components.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let isCloud = host.lowercased().hasSuffix(".atlassian.net")

        let queryPageID = components.queryItems?.first { $0.name == "pageId" }?.value
        let isViewPage = parts.last == "viewpage.action" && queryPageID != nil
        // ".../spaces/KEY/pages/123" (Cloud ve yeni Data Center)
        var pathPageID: String?
        if let spaces = parts.firstIndex(of: "spaces"), spaces + 2 < parts.count, parts[spaces + 2] == "pages" {
            pathPageID = parts[(spaces + 3)...].first { $0.allSatisfy(\.isNumber) }
        }
        guard isCloud || isViewPage || pathPageID != nil else { return nil }
        let pageID = isViewPage ? queryPageID : (pathPageID ?? queryPageID)
        guard let pageID, !pageID.isEmpty, pageID.allSatisfy(\.isNumber) else { return nil }

        // Taban yol: "spaces" ya da "pages" öncesi (ör. /wiki, /confluence).
        let markerIndex = parts.firstIndex { ["spaces", "pages", "display"].contains($0) } ?? parts.count
        let prefix = parts[..<markerIndex].map { "/" + $0 }.joined()
        var base = URLComponents()
        base.scheme = scheme
        base.host = host
        base.port = components.port
        base.path = prefix
        guard let baseURL = base.url else { return nil }
        return ConfluenceLink(deployment: isCloud ? .cloud : .server, baseURL: baseURL, pageID: pageID)
    }
}

enum URLImportError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized(host: String)
    case http(Int)
    case tooLarge
    case unsupportedContent(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "Geçerli bir http(s) adresi girin.")
        case .unauthorized(let host):
            String(localized: "\(host) erişim izni vermedi. Ayarlar → İçe Aktarma'dan bu site için Confluence e-postanızı ve API token'ınızı girin.")
        case .http(let status):
            String(localized: "Sunucu hata döndürdü (HTTP \(status)).")
        case .tooLarge:
            String(localized: "İçerik çok büyük (en fazla 20 MB).")
        case .unsupportedContent(let type):
            String(localized: "Bu içerik türü içe aktarılamıyor: \(type)")
        }
    }
}

/// Bir adresten not içeriği getirir: Confluence sayfaları (isteğe bağlı alt sayfalarıyla) resmi API'den,
/// diğer adresler içerik türüne göre (HTML, JSON, CSV, Markdown, Excel, Word).
struct URLImporter: Sendable {
    struct Result: Sendable {
        var sourceName: String
        var documents: [ImportedDocument]
    }

    static let maxBytes = 20 * 1024 * 1024
    static let maxPages = 100

    var credentials: ConfluenceCredentials?
    var session: URLSession = .shared

    static func validatedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    func documents(from url: URL, includeChildPages: Bool) async throws -> Result {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw URLImportError.invalidURL
        }
        if let link = ConfluenceLink.parse(url) {
            return try await confluence(link, includeChildPages: includeChildPages)
        }
        return try await generic(url)
    }

    // MARK: - Confluence

    private func confluence(_ link: ConfluenceLink, includeChildPages: Bool) async throws -> Result {
        var queue = [link.pageID]
        var seen = Set<String>()
        var documents: [ImportedDocument] = []
        var rootTitle: String?

        while let id = queue.first, documents.count < Self.maxPages {
            queue.removeFirst()
            guard seen.insert(id).inserted else { continue }
            let page = try await confluencePage(id, link: link)
            rootTitle = rootTitle ?? page.title
            documents.append(ImportedDocument(
                title: page.title,
                markdown: HTMLToMarkdown.convert(confluenceStorage: page.storage),
                createdAt: page.createdAt
            ))
            if includeChildPages {
                queue += try await confluenceChildren(id, link: link)
            }
        }
        return Result(sourceName: rootTitle ?? "Confluence", documents: documents)
    }

    private struct ConfluencePage { var title: String; var storage: String; var createdAt: Date? }

    private func confluencePage(_ id: String, link: ConfluenceLink) async throws -> ConfluencePage {
        let url: URL
        switch link.deployment {
        case .cloud:
            url = link.baseURL.appending(path: "api/v2/pages/\(id)").appending(queryItems: [URLQueryItem(name: "body-format", value: "storage")])
        case .server:
            url = link.baseURL.appending(path: "rest/api/content/\(id)").appending(queryItems: [URLQueryItem(name: "expand", value: "body.storage,history")])
        }
        let json = try await fetchJSON(url)
        let title = json["title"] as? String ?? String(localized: "Confluence sayfası")
        let body = (json["body"] as? [String: Any])?["storage"] as? [String: Any]
        let created = (json["createdAt"] as? String) ?? ((json["history"] as? [String: Any])?["createdDate"] as? String)
        return ConfluencePage(
            title: title,
            storage: body?["value"] as? String ?? "",
            createdAt: created.flatMap { ISO8601DateFormatter.withFractions.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        )
    }

    private func confluenceChildren(_ id: String, link: ConfluenceLink) async throws -> [String] {
        var url: URL? = switch link.deployment {
        case .cloud: link.baseURL.appending(path: "api/v2/pages/\(id)/children").appending(queryItems: [URLQueryItem(name: "limit", value: "250")])
        case .server: link.baseURL.appending(path: "rest/api/content/\(id)/child/page").appending(queryItems: [URLQueryItem(name: "limit", value: "200")])
        }
        var ids: [String] = []
        while let current = url, ids.count < Self.maxPages {
            let json = try await fetchJSON(current)
            ids += (json["results"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            // Cloud sayfalama: _links.next sitenin köküne göredir (/wiki/api/v2/...).
            if let next = (json["_links"] as? [String: Any])?["next"] as? String,
               var components = URLComponents(url: link.baseURL, resolvingAgainstBaseURL: false),
               let nextComponents = URLComponents(string: next) {
                components.path = nextComponents.path
                components.queryItems = nextComponents.queryItems
                url = components.url
            } else {
                url = nil
            }
        }
        return ids
    }

    private func fetchJSON(_ url: URL) async throws -> [String: Any] {
        let (data, _) = try await fetch(url, accept: "application/json")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLImportError.unsupportedContent("JSON")
        }
        return json
    }

    // MARK: - Genel adres

    private func generic(_ url: URL) async throws -> Result {
        let (data, response) = try await fetch(url, accept: "text/html,application/json,text/csv,text/plain,*/*;q=0.5")
        let mime = response.mimeType?.lowercased() ?? ""
        var fileName = response.suggestedFilename ?? url.lastPathComponent
        let fallbackTitle = url.host() ?? "URL"

        if mime.contains("html") || (mime.isEmpty && fileName.isEmpty) {
            guard let text = TextDecoding.string(from: data) else { throw URLImportError.unsupportedContent(mime) }
            let result = HTMLToMarkdown.convert(html: text)
            let title = result.title ?? fallbackTitle
            return Result(sourceName: title, documents: [ImportedDocument(title: title, markdown: result.markdown)])
        }
        // Uzantısı yoksa içerik türünden tahmin et.
        if (fileName as NSString).pathExtension.isEmpty {
            let ext = switch mime {
            case let type where type.contains("json"): "json"
            case let type where type.contains("csv"): "csv"
            case let type where type.contains("spreadsheetml"): "xlsx"
            case let type where type.contains("wordprocessingml"): "docx"
            case let type where type.contains("markdown"): "md"
            case let type where type.hasPrefix("text/"): "txt"
            default: ""
            }
            guard !ext.isEmpty else { throw URLImportError.unsupportedContent(mime) }
            fileName = (fileName.isEmpty ? fallbackTitle : fileName) + "." + ext
        }
        let documents = try FileImporter.documents(from: data, fileName: fileName)
        return Result(sourceName: fileName, documents: documents)
    }

    // MARK: - Ağ

    private func fetch(_ url: URL, accept: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let credentials, credentials.applies(to: url) {
            request.setValue(credentials.authorizationHeader(), forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request, delegate: RedirectGuard())
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw URLImportError.unauthorized(host: url.host() ?? "")
            default: throw URLImportError.http(http.statusCode)
            }
        }
        guard data.count <= Self.maxBytes else { throw URLImportError.tooLarge }
        return (data, response)
    }
}

/// Kimlik bilgisi taşıyan isteğin başka bir sunucuya yönlendirilmesini engeller.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        let original = task.originalRequest
        guard original?.value(forHTTPHeaderField: "Authorization") != nil else { return request }
        guard request.url?.host()?.lowercased() == original?.url?.host()?.lowercased(),
              request.url?.scheme == "https" || original?.url?.scheme == request.url?.scheme else {
            return nil
        }
        return request
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
