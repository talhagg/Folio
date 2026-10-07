# Folio — Claude Code ile yol haritası

## 0. Hazırlık (Xcode'da elle, ~10 dk)

1. Xcode → New Project → macOS → App. Product Name `Folio`, Interface SwiftUI, Language Swift, Storage **SwiftData**, "Host in CloudKit" ✓, "Include Tests" ✓.
2. Target → Signing & Capabilities:
   - **iCloud** → CloudKit ✓, container `iCloud.com.talha.folio` oluştur.
   - **Push Notifications** ekle (CloudKit değişiklik bildirimleri için).
   - **App Sandbox** → Outgoing Connections (Client) ✓.
   - Deployment target: macOS 14.0. Build Settings → Swift Language Version: 6.
3. Bu klasördeki `CLAUDE.md` ve `design/` klasörünü proje köküne kopyala. `git init` + ilk commit.
4. Proje kökünde `claude` çalıştır. Her adımda önce plan modunda planı onayla, sonra uygulat.

## Adım adım prompt'lar

Her birini sırayla yapıştır; bir adım derlenip testleri geçmeden sonrakine geçme.

**1 — Tasarım sistemi**
> CLAUDE.md'yi ve design/tokens.json'u oku. Tüm renkleri Asset Catalog'a Any/Dark color set olarak ekle, `Color.ds`, `Font.ds` ve `Metrics` (spacing, radius, layout ölçüleri) extension'larını yaz. Ardından DesignSystem/Components altında `ProgressBarView` (sm/md, label, değer), `StatusBadge`, `GroupTag`, `FilterChip` bileşenlerini yaz; her birine light ve dark `#Preview` ekle.

**2 — Veri modeli**
> CLAUDE.md'deki veri modelini CloudKit kurallarına uyarak SwiftData ile yaz (Notebook, NoteSection, Note, NoteTask, NoteStatus, GroupColor). Progress/status/isOverdue computed property'lerini ekle. CloudKit'li ve in-memory container factory'lerini yaz, `SampleData` ile 4 defter ve ~15 not üret. Progress ve status için Swift Testing testleri yaz.

**3 — Pencere iskeleti ve kenar çubuğu**
> 3 sütunlu `NavigationSplitView` kur. `SidebarSelection` enum'u (akıllı filtreler + notebook/section) ile kenar çubuğunu yap: akıllı filtreler, DEFTERLER başlığı, DisclosureGroup ile defter → bölüm ağacı, sayaçlar. Defter ekle/yeniden adlandır/sil ve bölüm ekle için bağlam menüleri ekle. design/app-window-light.png'ye görsel olarak yakın olsun.

**4 — Not listesi ve tarih filtresi**
> `NoteFilter` yaz: sidebar seçimi + `DateFilter` (all/today/week/month/custom aralık) + arama metninden `FetchDescriptor<Note>` üreten, `now` parametresi alan saf bir tip. Liste sütununu yap: üstte segmented DateFilter (Özel → iki DatePicker'lı popover), "N not · filtre" özeti, çipler; satırlar BUGÜN/DÜN/BU HAFTA/BU AY/DAHA ESKİ gruplu, sabitlenenler en üstte. `NoteRowView` başlık, 2 satır özet, tarih (gecikmişse kırmızı), GroupTag ve küçük progress gösterir. NoteFilter ve tarih gruplama için testler yaz.

**5 — Editör ve görevler**
> Editörü yap: breadcrumb + oluşturma/düzenleme/hedef tarihleri, serif başlık TextField, etiketli progress kartı (Bloke işaretleme menüsüyle), sürüklenebilir görev listesi (checkbox, metin, opsiyonel hedef tarih, Return ile yeni görev), altında markdown gövde için TextEditor. Okuma genişliği max 680pt. Her değişiklikte updatedAt güncellensin.

**6 — Arama**
> `.searchable` ile toolbar'a arama ekle (⌘F odaklasın). Başlık, gövde ve görev metinlerinde ara; eşleşmeyi NoteRowView'da `highlight` rengiyle AttributedString olarak vurgula. Arama aktifken liste başlığında sonuç sayısını göster.

**7 — macOS cilası**
> AppCommands ekle: ⌘N yeni not, ⇧⌘N yeni defter, ⌘⌫ sil (onaylı), ⌘P sabitle, ⌘1–4 akıllı filtreler. Notları sürükleyerek başka bölüme taşıma, defter/bölüm sıralaması (sortIndex). Boş durumlar (defter yok, not yok, sonuç yok). Pencere boyutu ve sütun genişliklerini SceneStorage ile hatırla.

**8 — Senkron ve kontrol**
> iCloud senkronunu iki Mac (veya Mac + ikinci kullanıcı hesabı) ile test etmek için kontrol listesi çıkar; senkron hata durumlarını loglayan küçük bir `SyncMonitor` ekle (NSPersistentCloudKitContainer event bildirimleri). Tüm testleri çalıştır, uyarıları temizle.

## Sonraki sürüm fikirleri

- Zengin metin editörü (NSTextView wrapper; macOS 26'da SwiftUI `TextEditor` + `AttributedString`).
- Etiketler, Quick Note menü çubuğu öğesi, Spotlight indeksleme (Core Spotlight), Widget.
