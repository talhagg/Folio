import SwiftUI

/// Ayarlar penceresi (⌘,): macOS Sistem Ayarları gibi gruplu, etiket solda kontrol sağda.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Genel", systemImage: "gearshape") }
            ImportSettingsView()
                .tabItem { Label("İçe Aktarma", systemImage: "square.and.arrow.down") }
        }
        .frame(width: 520)
    }
}

struct GeneralSettingsView: View {
    @Bindable private var theme = ThemeStore.shared
    @AppStorage(EditorTextSize.storageKey) private var textSizeRaw = EditorTextSize.normal.rawValue
    @AppStorage(Reminders.enabledKey) private var remindersEnabled = true
    @AppStorage(Reminders.hourKey) private var reminderHour = 9
    @AppStorage(QuickActions.hotKeyEnabledKey) private var hotKeyEnabled = true

    var body: some View {
        Form {
            Section("Görünüm") {
                Picker("Tema", selection: $theme.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Vurgu rengi") {
                    VStack(alignment: .trailing, spacing: Metrics.Spacing.s1) {
                        AccentSwatches(store: theme, size: 20)
                        Text(theme.accent.title)
                            .textStyle(.caption)
                            .foregroundStyle(Color.ds.inkSecondary)
                    }
                }
            }

            Section {
                Toggle("Hedef tarihlerde hatırlat", isOn: $remindersEnabled)
                Picker("Saat", selection: $reminderHour) {
                    ForEach(6..<23) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .disabled(!remindersEnabled)
            } header: {
                Text("Hatırlatıcılar")
            } footer: {
                Text("Hedef tarihi olan notlar ve görevler için o günün bu saatinde bildirim gelir.")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
            }
            .onChange(of: remindersEnabled) { ReminderScheduler.shared.scheduleSoon() }
            .onChange(of: reminderHour) { ReminderScheduler.shared.scheduleSoon() }

            Section {
                Toggle("⌃⌥N ile her yerden yapışkan not", isOn: $hotKeyEnabled)
                    .onChange(of: hotKeyEnabled) { _, enabled in GlobalHotKey.shared.setEnabled(enabled) }
            } header: {
                Text("Hızlı not")
            } footer: {
                Text("Menü çubuğundaki Folio simgesinden de hızlı not alabilirsiniz.")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
            }

            Section {
                Picker("Not yazı boyutu", selection: $textSizeRaw) {
                    ForEach(EditorTextSize.allCases) { size in
                        Text(size.menuTitle).tag(size.rawValue)
                    }
                }
            } header: {
                Text("Yazı")
            } footer: {
                Text("Yazarken üstteki biçim çubuğundan ya da ⌘+ / ⌘- ile de değiştirebilirsiniz.")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 560)
    }
}

struct ImportSettingsView: View {
    @State private var site = ""
    @State private var email = ""
    @State private var token = ""
    @State private var status: String?
    @State private var hasSaved = false

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Her sayfa token olmadan içe aktarılabilir: sayfa uygulamanın içinde açılır, gerekirse orada giriş yaparsınız.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.ds.accent)
                }
                .textStyle(.callout)
            }

            Section {
                TextField("Site", text: $site, prompt: Text("sirket.atlassian.net"))
                TextField("E-posta", text: $email, prompt: Text("Yalnızca Cloud için"))
                SecureField("API token", text: $token)
                HStack {
                    if let status {
                        Text(status)
                            .textStyle(.caption)
                            .foregroundStyle(Color.ds.inkSecondary)
                    }
                    Spacer()
                    if hasSaved {
                        Button("Kaldır", role: .destructive, action: remove)
                    }
                    Button("Kaydet", action: save)
                        .disabled(site.trimmingCharacters(in: .whitespaces).isEmpty || token.isEmpty)
                }
            } header: {
                Text("Confluence alt sayfaları (isteğe bağlı)")
            } footer: {
                Text("Bir sayfayı alt sayfalarıyla birlikte toplu içe aktarmak için. Cloud: id.atlassian.com → Güvenlik → API token. Server: profil → Kişisel erişim token'ları. Token Keychain'de saklanır ve yalnızca bu siteye gönderilir.")
                    .textStyle(.caption)
                    .foregroundStyle(Color.ds.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 400)
        .onAppear(perform: load)
    }

    private func load() {
        guard let saved = ConfluenceCredentials.load() else { return }
        site = saved.site
        email = saved.email
        token = saved.token
        hasSaved = true
    }

    private func save() {
        do {
            try ConfluenceCredentials(site: site, email: email, token: token).save()
            hasSaved = true
            status = String(localized: "Kaydedildi.")
        } catch {
            status = String(localized: "Kaydedilemedi: \(error.localizedDescription)")
        }
    }

    private func remove() {
        ConfluenceCredentials.delete()
        site = ""
        email = ""
        token = ""
        hasSaved = false
        status = String(localized: "Bilgiler silindi.")
    }
}
