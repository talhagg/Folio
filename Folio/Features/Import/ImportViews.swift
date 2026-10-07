import SwiftData
import SwiftUI

/// URL'den içe aktarma sayfası.
struct URLImportView: View {
    /// Başarılı içe aktarmadan sonra oluşan bölümle çağrılır.
    let onImported: (NoteSection, Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var address = ""
    @State private var includeChildPages = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    private var url: URL? { URLImporter.validatedURL(address) }
    private var confluence: ConfluenceLink? { url.flatMap(ConfluenceLink.parse) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.s3) {
            Text("URL'den İçe Aktar")
                .textStyle(.windowTitle)
                .foregroundStyle(Color.ds.ink)
            Text("Confluence sayfası, web sayfası ya da JSON, CSV, Excel, Word, Markdown dosyası adresi.")
                .textStyle(.callout)
                .foregroundStyle(Color.ds.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://sirket.atlassian.net/wiki/spaces/…", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(start)
                .disabled(isLoading)

            if let confluence {
                VStack(alignment: .leading, spacing: Metrics.Spacing.s2) {
                    Label(
                        confluence.deployment == .cloud ? "Confluence Cloud sayfası" : "Confluence Server sayfası",
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.accent)
                    Toggle("Alt sayfaları da içe aktar (en fazla \(URLImporter.maxPages))", isOn: $includeChildPages)
                        .textStyle(.callout)
                    if ConfluenceCredentials.load()?.applies(to: confluence.baseURL) != true {
                        HStack(spacing: Metrics.Spacing.s1) {
                            Text("Herkese açık olmayan sayfalar için API token gerekir.")
                                .foregroundStyle(Color.ds.inkSecondary)
                            Button("Ayarlar…") { openSettings() }
                                .buttonStyle(.link)
                        }
                        .textStyle(.caption)
                    }
                }
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
                Button("İçe Aktar", action: start)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ds.accent)
                    .disabled(url == nil || isLoading)
            }
        }
        .padding(Metrics.Spacing.s4)
        .frame(width: 480)
    }

    private func start() {
        guard let url, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let importer = URLImporter(credentials: ConfluenceCredentials.load())
        let includeChildPages = includeChildPages
        task = Task {
            do {
                let result = try await importer.documents(from: url, includeChildPages: includeChildPages)
                if let section = context.importDocuments(result.documents, sourceName: result.sourceName) {
                    onImported(section, result.documents.count)
                    dismiss()
                } else {
                    errorMessage = ImportError.empty.localizedDescription
                }
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
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

/// Ayarlar penceresi (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Genel", systemImage: "paintpalette") }
            ImportSettingsView()
                .tabItem { Label("İçe Aktarma", systemImage: "square.and.arrow.down") }
        }
        .frame(width: 480)
        .padding(Metrics.Spacing.s4)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(EditorTextSize.storageKey) private var textSizeRaw = EditorTextSize.normal.rawValue

    var body: some View {
        Form {
            Section {
                ThemePicker()
                    .padding(.vertical, Metrics.Spacing.s1)
            } header: {
                Text("Tema")
            }
            Picker("Not yazı boyutu", selection: $textSizeRaw) {
                ForEach(EditorTextSize.allCases) { size in
                    Text(size.title).tag(size.rawValue)
                }
            }
            Text("Not yazarken üstteki biçim çubuğundan ya da ⌘+ / ⌘- ile de değiştirebilirsiniz.")
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkSecondary)
        }
    }
}

private struct ImportSettingsView: View {
    @State private var site = ""
    @State private var email = ""
    @State private var token = ""
    @State private var status: String?
    @State private var hasSaved = false

    var body: some View {
        Form {
            Section {
                TextField("Site", text: $site, prompt: Text("sirket.atlassian.net"))
                TextField("E-posta", text: $email, prompt: Text("Cloud için; Server'da boş bırakın"))
                SecureField("API token", text: $token)
            } header: {
                Text("Confluence")
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.Spacing.s1) {
                    Text("Cloud: id.atlassian.com → Güvenlik → API token oluştur. Server/Data Center: profil → Kişisel erişim token'ları.")
                    Text("Token Keychain'de saklanır ve yalnızca bu siteye giden isteklere eklenir.")
                }
                .textStyle(.caption)
                .foregroundStyle(Color.ds.inkSecondary)
            }

            HStack {
                if let status {
                    Text(status)
                        .textStyle(.caption)
                        .foregroundStyle(Color.ds.inkSecondary)
                }
                Spacer()
                if hasSaved {
                    Button("Kaldır", role: .destructive) {
                        ConfluenceCredentials.delete()
                        site = ""
                        email = ""
                        token = ""
                        hasSaved = false
                        status = String(localized: "Bilgiler silindi.")
                    }
                }
                Button("Kaydet") {
                    do {
                        try ConfluenceCredentials(site: site, email: email, token: token).save()
                        hasSaved = true
                        status = String(localized: "Kaydedildi.")
                    } catch {
                        status = String(localized: "Kaydedilemedi: \(error.localizedDescription)")
                    }
                }
                .disabled(site.trimmingCharacters(in: .whitespaces).isEmpty || token.isEmpty)
            }
        }
        .onAppear {
            if let saved = ConfluenceCredentials.load() {
                site = saved.site
                email = saved.email
                token = saved.token
                hasSaved = true
            }
        }
    }
}
