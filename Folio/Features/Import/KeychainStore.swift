import Foundation
import Security

/// Uygulamanın kendi Keychain kayıtları (genel parola sınıfı).
enum KeychainStore {
    static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Confluence erişim bilgileri. Cloud: e-posta + API token (Basic); Server/Data Center: kişisel erişim
/// token'ı (Bearer, e-posta boş). Yalnızca `site` ile aynı sunucuya giden isteklere eklenir.
struct ConfluenceCredentials: Codable, Equatable, Sendable {
    var site: String
    var email: String
    var token: String

    private static let service = "com.talha.folio.confluence"
    private static let account = "default"

    /// "https://sirket.atlassian.net/wiki" ya da "sirket.atlassian.net" → "sirket.atlassian.net"
    var host: String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        return URL(string: withScheme)?.host()?.lowercased() ?? trimmed.lowercased()
    }

    func authorizationHeader() -> String {
        if email.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Bearer \(token)"
        }
        return "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
    }

    func applies(to url: URL) -> Bool {
        guard !token.isEmpty, let host = url.host()?.lowercased() else { return false }
        return host == self.host
    }

    static func load() -> ConfluenceCredentials? {
        KeychainStore.load(service: service, account: account).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save() throws {
        try KeychainStore.save(JSONEncoder().encode(self), service: Self.service, account: Self.account)
    }

    static func delete() {
        KeychainStore.delete(service: service, account: account)
    }
}
