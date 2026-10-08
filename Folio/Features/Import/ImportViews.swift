import SwiftData
import SwiftUI

/// URL'den içe aktarma. Dosya adresleri doğrudan indirilir; web sayfaları (Confluence dahil) pencerenin
/// içinde açılır — gerekirse kullanıcı orada giriş yapar — ve "Bu Sayfayı İçe Aktar" ile nota çevrilir.
/// Kayıtlı Confluence token'ı varsa sayfa API'den (istenirse alt sayfalarıyla) alınır.
struct URLImportView: View {
    /// Başarılı içe aktarmadan sonra oluşan bölümle çağrılır.
    let onImported: (NoteSection, Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var includeChildPages = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var page: WebPage?

    private var url: URL? { URLImporter.validatedURL(address) }
    private var confluence: ConfluenceLink? { url.flatMap(ConfluenceLink.parse) }
    private var credentialsApply: Bool {
        guard let confluence else { return false }
        return ConfluenceCredentials.load()?.applies(to: confluence.baseURL) == true
    }

    static let fileExtensions: Set<String> = ["json", "csv", "tsv", "xlsx", "docx", "md", "markdown", "txt"]

    var body: some View {
        Group {
            if let page {
                browser(page)
            } else {
                addressForm
            }
        }
        .animation(.snappy(duration: 0.2), value: page != nil)
    }

    // MARK: - Adres

    private var addressForm: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            Text("URL'den İçe Aktar")
                .textStyle(.windowTitle)
                .foregroundStyle(Color.ds.ink)
            Text("Web sayfası, Confluence sayfası ya da JSON, CSV, Excel, Word, Markdown dosyası adresi.")
                .textStyle(.callout)
                .foregroundStyle(Color.ds.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://…", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(start)
                .disabled(isLoading)

            if confluence != nil, credentialsApply {
                Toggle("Alt sayfaları da içe aktar (en fazla \(URLImporter.maxPages))", isOn: $includeChildPages)
                    .textStyle(.callout)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .textStyle(.callout)
                    .foregroundStyle(Color.ds.statusBlocked)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                    Text("Okunuyor…")
                        .textStyle(.callout)
                        .foregroundStyle(Color.ds.inkSecondary)
                }
                Spacer()
                Button("Vazgeç") {
                    task?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(goButtonTitle, action: start)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ds.accent)
                    .disabled(url == nil || isLoading)
            }
        }
        .padding(Metrics.Spacing.s4)
        .frame(width: 480)
    }

    private var isFileURL: Bool {
        guard let url else { return false }
        return Self.fileExtensions.contains(url.pathExtension.lowercased())
    }

    private var goButtonTitle: LocalizedStringKey {
        isFileURL || credentialsApply ? "İçe Aktar" : "Sayfayı Aç"
    }

    private func start() {
        guard let url, !isLoading else { return }
        errorMessage = nil
        // Web sayfası: uygulama içinde aç, kullanıcı gerekirse giriş yapsın.
        guard isFileURL || credentialsApply else {
            page = WebPage(url: url)
            return
        }
        isLoading = true
        let importer = URLImporter(credentials: ConfluenceCredentials.load())
        let includeChildPages = includeChildPages
        task = Task {
            do {
                let result = try await importer.documents(from: url, includeChildPages: includeChildPages)
                finish(result.documents, sourceName: result.sourceName)
            } catch is CancellationError {
            } catch {
                // Token reddedildiyse ya da dosya indirilemediyse sayfayı tarayıcıda dene.
                if !isFileURL {
                    page = WebPage(url: url)
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    private func finish(_ documents: [ImportedDocument], sourceName: String) {
        if let section = context.importDocuments(documents, sourceName: sourceName) {
            onImported(section, documents.count)
            dismiss()
        } else {
            errorMessage = ImportError.empty.localizedDescription
        }
    }

    // MARK: - Tarayıcı

    private func browser(_ page: WebPage) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.Spacing.s2) {
                Button { page.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!page.canGoBack)
                    .help(Text("Geri"))
                Button { page.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help(Text("Yenile"))
                HStack(spacing: 6) {
                    Image(systemName: page.url?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ds.inkTertiary)
                    Text(page.url?.host() ?? address)
                        .textStyle(.callout)
                        .foregroundStyle(Color.ds.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if page.isLoading { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, Metrics.Spacing.s2)
                .frame(height: 26)
                .background(Color.ds.surfaceHover.opacity(0.6), in: RoundedRectangle(cornerRadius: Metrics.Radius.md))

                Button("Vazgeç") {
                    self.page = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    importCurrentPage(page)
                } label: {
                    Label("Bu Sayfayı İçe Aktar", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ds.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(page.isLoading || isLoading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Metrics.Spacing.s3)
            .padding(.vertical, Metrics.Spacing.s2)

            Text("Giriş gerekiyorsa sayfada oturum açın; sonra \"Bu Sayfayı İçe Aktar\"a basın.")
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.Spacing.s3)
                .padding(.bottom, Metrics.Spacing.s2)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.statusBlocked)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.Spacing.s3)
                    .padding(.bottom, Metrics.Spacing.s2)
            }

            Rectangle().fill(Color.ds.separator).frame(height: 1)
            WebView(page: page)
        }
        .frame(width: 980, height: 720)
    }

    private func importCurrentPage(_ page: WebPage) {
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let snapshot = try await page.contentSnapshot()
                let result = HTMLToMarkdown.convert(html: snapshot.html)
                let title = WebPage.cleanTitle(snapshot.title) ?? result.title ?? page.url?.host() ?? "URL"
                guard !result.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = ImportError.empty.localizedDescription
                    return
                }
                finish([ImportedDocument(title: title, markdown: result.markdown)], sourceName: title)
            } catch {
                errorMessage = String(localized: "Sayfa okunamadı: \(error.localizedDescription)")
            }
        }
    }
}

/// Dosyaları içe aktarır; her dosya "İçe Aktarılanlar" altında kendi bölümüne gider.
@MainActor
enum FileImportRunner {
    struct Summary {
        var lastSection: NoteSection?
        var noteCount = 0
        var failures: [String] = []

        var message: String {
            var lines: [String] = []
            if noteCount > 0 {
                lines.append(String(localized: "\(noteCount) not \"\(ModelContext.importNotebookName)\" defterine eklendi."))
            }
            lines += failures
            return lines.joined(separator: "\n")
        }
    }

    static func run(_ urls: [URL], in context: ModelContext) -> Summary {
        var summary = Summary()
        for url in urls {
            do {
                let documents = try FileImporter.documents(from: url)
                if let section = context.importDocuments(documents, sourceName: url.deletingPathExtension().lastPathComponent) {
                    summary.lastSection = section
                    summary.noteCount += documents.count
                }
            } catch {
                summary.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return summary
    }
}
