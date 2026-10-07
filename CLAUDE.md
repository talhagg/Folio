# Folio — macOS not uygulaması

OneNote benzeri, macOS'a özel not uygulaması: Defter → Bölüm → Not hiyerarşisi, not başına ilerleme (progress), tarihe göre filtreleme, global arama. iCloud ile senkron.

## Teknik çerçeve

- Swift 6 dil modu, strict concurrency. SwiftUI + SwiftData. Minimum **macOS 14 Sonoma**.
- Yalnızca macOS hedefi (Catalyst yok). AppKit sadece SwiftUI'ın yetmediği yerde (`NSViewRepresentable`).
- Üçüncü parti bağımlılık yok; eklemeden önce sor.
- `@Observable` kullan; `ObservableObject`/`@Published` kullanma.
- Arayüz metinleri Türkçe, `Localizable.xcstrings` üzerinden (`String(localized:)` / `Text("…")`).

## SwiftData + CloudKit kuralları (ihlali senkronu sessizce bozar)

- Her stored property **ya default değerli ya optional** olmalı.
- Tüm relationship'ler **optional** olmalı (`var notes: [Note]? = []`), iki tarafı da `inverse:` ile tanımlı.
- `@Attribute(.unique)` **kullanma**.
- SwiftData ilişkileri sırasızdır: sıralama için `sortIndex: Double` tut.
- Enum'ları `rawValue` (String) olarak sakla, computed property ile aç (`statusRaw` ↔ `status`).
- Production şemaya gönderildikten sonra yalnızca **ekleyerek** değişiklik yap (alan silme/yeniden adlandırma yok).
- Container: `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.talha.folio"))`. Preview ve testler için `isStoredInMemoryOnly: true` ve `cloudKitDatabase: .none`.

## Veri modeli

```
Notebook   id, name, colorRaw (GroupColor), sortIndex, createdAt, sections: [NoteSection]?
NoteSection id, name, sortIndex, createdAt, notebook: Notebook?, notes: [Note]?
Note       id, title, body (String, markdown), createdAt, updatedAt, dueDate: Date?,
           isPinned, statusOverrideRaw: String? (sadece "blocked" için), section: NoteSection?, tasks: [NoteTask]?,
           deletedAt: Date? (Son Silinenler), trashedFromPath: String?
NoteTask   id, text, isDone, dueDate: Date?, sortIndex, note: Note?
```

- `SwiftUI.Section` ile çakışmasın diye model adı **`NoteSection`**.
- `Note.progress` computed: `done / total` (görev yoksa `nil`).
- `Note.status` computed: override `blocked` ise Bloke; yoksa progress 0 → todo, 0<p<1 → doing, 1 → done.
- `Note.isOverdue`: `dueDate < now && status != .done`.
- Her düzenlemede `updatedAt = .now`.
- Silme önce **Son Silinenler**'e taşır (`deletedAt`); 90 gün sonra açılışta/öne gelince kalıcı silinir. Defter/bölüm silinince notları çöpe gider, kaybolmaz. Çöpteki notlar diğer tüm görünüm ve sayaçlardan hariçtir.
- SwiftData inverse'i ilişkinin yalnızca tek tarafında (to-many tarafı) tanımlanır; iki tarafta yazmak derleme hatası verir.
- `#Predicate` iki seviyeli opsiyonel zinciri (`section?.notebook?.id`) SQL'e çeviremez; böyle koşullar bellekte uygulanır.

## Klasör yapısı

```
Folio/
  App/            FolioApp.swift, AppCommands.swift, ModelContainer+Folio.swift
  Models/         Notebook, NoteSection, Note, NoteTask, NoteStatus, GroupColor
  Features/
    Sidebar/      SidebarView, SidebarSelection
    NoteList/     NoteListView, NoteRowView, DateGrouping
    Editor/       NoteEditorView, TaskListView
    Filters/      DateFilter, NoteFilter (predicate builder)
  DesignSystem/   Colors.swift, Typography.swift, Metrics.swift, Components/
  Preview Content/ SampleData.swift
FolioTests/      NoteFilterTests, NoteProgressTests, DateGroupingTests
```

## Tasarım sistemi

Kaynak: `design/tokens.json` (Light/Dark). Hedef görünüm: `design/app-window-light.png`, `design/app-window-dark.png`.

- Renkleri **Asset Catalog color set** olarak ekle (Any + Dark), adlar tokens.json ile aynı: `window-bg`, `sidebar-bg`, `surface`, `surface-raised`, `surface-hover`, `selection`, `separator`, `control-border`, `ink`, `ink-secondary`, `ink-tertiary`, `accent`, `accent-hover`, `on-accent`, `accent-soft`, `status-todo|doing|done|blocked`, `group-clay|amber|moss|teal|slate|plum`, `highlight`.
- `Color.ds.ink` gibi tip güvenli erişim (`extension Color { enum ds }`), view'larda hex yazma.
- Uygulamanın accent color'ı `accent`.
- Tipografi (`Font.ds.*`): window-title 15/600, headline 13/600, body 13/400, callout 12, caption 11/500, section-label 11/600 büyük harf + 0.04em tracking (sans = sistem fontu); note-title 28/600, note-heading 19/600, note-body 15 (serif = `.system(design: .serif)` → New York); code 13 (`.monospaced`).
- Spacing 4/8/12/16/24/40, radius 4/6/10/12. Kenar çubuğu 220pt, liste 300pt, satır 28pt.
- Durum her zaman **ikon + metin** (renk tek başına yetmez). SF Symbols: `circle`, `circle.lefthalf.filled`, `checkmark.circle`, `xmark.circle`.
- Defter rengi yalnızca nokta/ikon; yanında her zaman defter adı.
- Sütunlar 1pt separator ile ayrılır, gölge yok. Gölge sadece popover'da.

## Ekran davranışları

- `NavigationSplitView` 3 sütun. Sidebar: akıllı filtreler (Tüm Notlar, Bugün, Devam Edenler, Sabitlenenler) + DEFTERLER ağacı (`DisclosureGroup`), sayaçlar sağda.
- Liste: üstte `DateFilter` segmented (Tümü/Bugün/Bu Hafta/Bu Ay/Özel → iki DatePicker'lı popover), "N not · filtre" özeti, kaldırılabilir filtre çipleri. Satırlar BUGÜN/DÜN/BU HAFTA/BU AY/DAHA ESKİ başlıklarıyla gruplu, sabitlenenler en üstte.
- Editör: breadcrumb + tarihler, serif başlık, etiketli progress kartı, görev listesi, markdown gövde. Okuma genişliği max 680pt.
- Arama: `.searchable` toolbar'da, ⌘F; başlık + gövde + görev metninde `localizedStandardContains`. Eşleşme `highlight` ile vurgulanır.
- Tarih hesapları `Calendar.current` ile (hafta başlangıcı locale'den), "şimdi" test edilebilir olsun diye `now: Date` parametre olarak geçilir.

## Çalışma şekli

- Her adımdan sonra derle (`xcodebuild -scheme Folio -destination 'platform=macOS' build`) ve testleri çalıştır; hata varken bir sonraki işe geçme.
- Her view için `#Preview` yaz, `SampleData` ile in-memory container kullan.
- Küçük, odaklı commit'ler; mesajlar İngilizce, imperative.
- Mantığı (filtre, gruplama, progress) view'dan ayır ve Swift Testing (`@Test`) ile test et.
