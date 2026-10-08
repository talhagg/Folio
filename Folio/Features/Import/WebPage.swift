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

    /// Testler için: verilen HTML'i yükler.
    convenience init(html: String) {
        self.init(url: nil)
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.test"))
    }

    convenience init(url: URL) {
        self.init(url: Optional(url))
        webView.load(URLRequest(url: url))
    }

    private init(url: URL?) {
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
    }

    struct Snapshot: Sendable {
        var title: String
        var html: String
    }

    /// Sayfanın asıl içeriği: Confluence (Server ve Cloud), makale ya da ana bölüm; yoksa gövde.
    /// Tablolar (ve role="table"/"grid" ile çizilenler) ekranda görünen metinleriyle temiz birer
    /// `<table>`'a dönüştürülür: hücrelerdeki düğmeler, simgeler ve iç içe kutular tabloyu bozmaz.
    static let contentScript = """
    (() => {
      const selectors = ['#main-content', '.wiki-content', '[data-testid="renderer-page"]', '.ak-renderer-document',
                         '.mw-parser-output', 'article', 'main', '[role="main"]'];
      let root = null;
      for (const selector of selectors) {
        const element = document.querySelector(selector);
        if (element && element.innerText.trim().length > 40) { root = element; break; }
      }
      root = root || document.body || document.documentElement;

      const tableSelector = 'table, [role="table"], [role="grid"], [role="treegrid"]';
      const topLevel = (list) => list.filter(t => !(t.parentElement && t.parentElement.closest(tableSelector)));
      const escape = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      // Hücre metni: düğme, simge ve gizli öğeler atılır; paragraflar arasına boşluk konur.
      const textOf = (cell) => {
        const copy = cell.cloneNode(true);
        copy.querySelectorAll('button, svg, img, style, script, [aria-hidden="true"]').forEach(node => node.remove());
        copy.querySelectorAll('p, div, li, br').forEach(node => node.after(' '));
        return escape((copy.textContent || '').replace(/\\s+/g, ' ').trim());
      };

      const simplified = topLevel([...root.querySelectorAll(tableSelector)]).map(table => {
        const native = table.tagName === 'TABLE';
        const rows = native ? [...table.rows]
          : [...table.querySelectorAll('[role="row"]')].filter(r => r.closest(tableSelector) === table);
        const html = rows.map(row => {
          const cells = native ? [...row.cells]
            : [...row.querySelectorAll('[role="cell"],[role="gridcell"],[role="columnheader"],[role="rowheader"]')]
                .filter(c => c.closest('[role="row"]') === row);
          if (!cells.length) { return ''; }
          return '<tr>' + cells.map(cell => {
            const header = cell.tagName === 'TH' || cell.getAttribute('role') === 'columnheader';
            const span = parseInt(cell.getAttribute('colspan') || '1', 10) || 1;
            const tag = header ? 'th' : 'td';
            return '<' + tag + (span > 1 ? ' colspan="' + span + '"' : '') + '>' + textOf(cell) + '</' + tag + '>';
          }).join('') + '</tr>';
        }).join('');
        return '<table>' + html + '</table>';
      });

      const clone = root.cloneNode(true);
      topLevel([...clone.querySelectorAll(tableSelector)]).forEach((table, index) => {
        if (simplified[index] === undefined) { return; }
        const holder = document.createElement('div');
        holder.innerHTML = simplified[index];
        table.replaceWith(holder.firstChild);
      });
      return clone.outerHTML;
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
