# Güvenlik

## Açık bildirme

Bir güvenlik açığı bulursanız lütfen herkese açık issue açmak yerine GitHub'daki
**Security → Report a vulnerability** (özel bildirim) özelliğini kullanın.

## Güvenlik incelemesi — v0.2 (7 Ekim 2026)

### Tehdit yüzeyi

| Alan | Durum |
|---|---|
| Ağ erişimi | Kodda `URLSession`, soket ya da web içeriği yok. Tek ağ trafiği, sistemin yönettiği iCloud (CloudKit) özel veritabanı senkronudur; veriler kullanıcının kendi iCloud hesabında kalır. |
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
- İzinler: `app-sandbox`, `network.client` (CloudKit için), iCloud/CloudKit (`Production`), push (`production`).
  `get-task-allow` (hata ayıklama) yok.
- İkili dosyada yerel yol, kişisel bilgi ya da hata ayıklama bayrağı (`-seedSampleData`, yalnızca DEBUG) yok.
- Depo geçmişinde parola, anahtar ya da token yok; Apple Developer Team ID `Config/Local.xcconfig`'e (git dışı) taşındı.

### Bilinen sınırlamalar

1. **v0.1 ad-hoc imzalıydı** ve notarize edilmemişti; v0.2 ve sonrası notarize edilmiştir.
2. **Yerel veriler şifrelenmemiş SQLite deposunda** (`~/Library/Containers/com.talha.folio`). Disk şifrelemesi için FileVault'a dayanır.
   iCloud'daki kopya Apple'ın CloudKit özel veritabanında, kullanıcının hesabıyla korunur.
3. **Depo açılamazsa uygulama kapanır** (`fatalError`). Veri kaybına yol açmaz ama bozuk bir depo uygulamanın açılmasını engeller.
