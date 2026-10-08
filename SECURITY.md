# Güvenlik

## Açık bildirme

Bir güvenlik açığı bulursanız lütfen herkese açık issue açmak yerine GitHub'daki
**Security → Report a vulnerability** (özel bildirim) özelliğini kullanın.

## Güvenlik incelemesi — v0.5.1 (8 Ekim 2026)

### Tehdit yüzeyi

| Alan | Durum |
|---|---|
| Ağ erişimi | iCloud (CloudKit) özel veritabanı senkronu ve yalnızca kullanıcının başlattığı **URL'den içe aktarma**. URL içe aktarma yalnızca `http(s)` kabul eder, 30 sn zaman aşımı ve 20 MB sınırı vardır; içerik çalıştırılmaz (JavaScript yok), metne dönüştürülür. |
| Uygulama içi tarayıcı | URL içe aktarmada sayfa WebKit ile gösterilir; yalnızca `http(s)` gezinmesine izin verilir, indirmeler açılmaz. Uygulama sayfaya yalnızca içeriği okuyan sabit bir betik çalıştırır (`outerHTML`), sayfaya veri yazmaz. Oturum çerezleri uygulamanın kendi WebKit deposunda kalır. |
| Bildirimler | Yalnızca yerel bildirimler (UserNotifications); içerik not başlığı ve konumudur, sunucuya bir şey gönderilmez. |
| Genel kısayol | ⌃⌥N, Carbon `RegisterEventHotKey` ile kaydedilir; klavye dinlenmez, erişilebilirlik izni gerekmez. |
| Spotlight | Not başlığı, özeti ve etiketleri yalnızca bu Mac'in Spotlight dizinine yazılır; çöpe atılan notlar çıkarılır. |
| Ekler | Kullanıcının seçtiği/yapıştırdığı dosyalar 25 MB sınırıyla saklanır; açılırken geçici klasöre yazılıp varsayılan uygulamayla açılır, uygulama içinde çalıştırılmaz. |
| Kimlik bilgileri | Confluence token'ı Keychain'de (`kSecAttrAccessibleWhenUnlocked`) saklanır; yalnızca kayıtlı site ile **aynı sunucuya** giden isteklere eklenir. Kimlik bilgili bir istek başka bir sunucuya yönlendirilirse iptal edilir. |
| Dosya içe/dışa aktarma | Yalnızca kullanıcının seçtiği/sürüklediği dosyalar okunur ve yalnızca kaydetme penceresinde seçilen konuma yazılır (`files.user-selected.read-write`). Boyut 50 MB, ZIP açılmış boyutu 100 MB ile sınırlı (zip bombası koruması); Office makroları ve gömülü nesneler yok sayılır. |
| Dosya sistemi | Yalnızca SwiftData deposu (uygulama sandbox'ı içinde) ve `UserDefaults` (pencere sütun genişlikleri). |
| Süreç / dinamik kod | `Process`, `dlopen`, script çalıştırma yok. |
| Üçüncü parti bağımlılık | Yok. |
| Kullanıcı girdisi | Not metni düz metin olarak saklanır ve gösterilir; markdown/HTML yorumlanmaz, enjeksiyon yüzeyi yok. Önizleme regex'leri doğrusal (ReDoS yok). |
| Sürükle-bırak | Yük `folio.<tür>:<UUID>` biçiminde doğrulanır; başka uygulamalardan gelen metin yalnızca kullanıcının kendi notlarıyla eşleşebilir. |
| Günlükler | Yalnızca depo açma hataları (`OSLog`), not içeriği loglanmaz. |

### Dağıtım (DMG)

- **Developer ID ile imzalı ve Apple tarafından notarize edilmiş**; notarization bileti DMG'ye iliştirilmiş (stapled).
  `spctl` sonucu: `accepted — source=Notarized Developer ID`.
- Mach-O universal (arm64 + x86_64), **hardened runtime** açık.
- İzinler: `app-sandbox`, `network.client` (CloudKit ve URL içe aktarma), `files.user-selected.read-write`, iCloud/CloudKit (`Production`), push (`production`).
  `get-task-allow` (hata ayıklama) yok.
- İkili dosyada yerel yol, kişisel bilgi ya da hata ayıklama bayrağı (`-seedSampleData`, yalnızca DEBUG) yok.
- Depo geçmişinde parola, anahtar ya da token yok; Apple Developer Team ID `Config/Local.xcconfig`'e (git dışı) taşındı.

### Bilinen sınırlamalar

1. **v0.1 ad-hoc imzalıydı** ve notarize edilmemişti; v0.2 ve sonrası notarize edilmiştir.
2. **Yerel veriler şifrelenmemiş SQLite deposunda** (`~/Library/Containers/com.talha.folio`). Disk şifrelemesi için FileVault'a dayanır.
   iCloud'daki kopya Apple'ın CloudKit özel veritabanında, kullanıcının hesabıyla korunur.
3. **Depo açılamazsa uygulama kapanır** (`fatalError`). Veri kaybına yol açmaz ama bozuk bir depo uygulamanın açılmasını engeller.
