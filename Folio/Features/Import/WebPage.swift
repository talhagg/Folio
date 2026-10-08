import SwiftUI
import WebKit

/// İçe aktarma tarayıcısı: sayfayı gösterir, kullanıcı gerekirse giriş yapar; içerik yalnızca okunur.
/// Oturum çerezleri uygulamanın WebKit deposunda kalır (sonraki içe aktarmalarda yeniden giriş gerekmez).
@MainActor
@Observable
final class WebPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var url: URL?
    private(set) var isLoading = true
    private(set) var canGoBack = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(url: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.url = url
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.url = view.url } },
            webView.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            webView.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
        ]
        webView.load(URLRequest(url: url))
    }

    struct Snapshot: Sendable {
        var title: String
        var html: String
    }

    /// Sayfanın asıl içeriği: Confluence (Server ve Cloud), makale ya da ana bölüm; yoksa gövde.
    static let contentScript = """
    (() => {
      const selectors = ['#main-content', '.wiki-content', '[data-testid="renderer-page"]', '.ak-renderer-document',
                         '.mw-parser-output', 'article', 'main', '[role="main"]'];
      for (const selector of selectors) {
        const element = document.querySelector(selector);
        if (element && element.innerText.trim().length > 40) { return element.outerHTML; }
      }
      return document.body ? document.body.outerHTML : document.documentElement.outerHTML;
    })()
    """

    func contentSnapshot() async throws -> Snapshot {
        let html = try await evaluate(Self.contentScript)
        let title = (try? await evaluate("document.title")) ?? ""
        return Snapshot(title: title, html: "<html><body>\(html)</body></html>")
    }

    private func evaluate(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String ?? "")
                }
            }
        }
    }

    /// "Sayfa Adı - Alan - Confluence" → "Sayfa Adı"
    nonisolated static func cleanTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("Confluence"), let first = trimmed.components(separatedBy: " - ").first, !first.isEmpty {
            return first.trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // Yalnızca http(s) gezinmesine izin ver; indirmeleri açma.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let scheme = action.request.url?.scheme?.lowercased() else { return .cancel }
        return ["http", "https", "about"].contains(scheme) ? .allow : .cancel
    }
}

struct WebView: NSViewRepresentable {
    let page: WebPage

    func makeNSView(context: Context) -> WKWebView { page.webView }
    func updateNSView(_ webView: WKWebView, context: Context) {}
}
