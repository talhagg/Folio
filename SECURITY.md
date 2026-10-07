# Güvenlik

## Açık bildirme

Bir güvenlik açığı bulursanız lütfen herkese açık issue açmak yerine GitHub'daki
**Security → Report a vulnerability** (özel bildirim) özelliğini kullanın.

## Güvenlik incelemesi — v0.1 (7 Ekim 2026)

### Tehdit yüzeyi

| Alan | Durum |
|---|---|
| Ağ erişimi | Yok. Kodda `URLSession`, soket ya da web içeriği yok. DMG sürümünde ağ izni de yok. |
| Dosya sistemi | Yalnızca SwiftData deposu (uygulama sandbox'ı içinde) ve `UserDefaults` (pencere sütun genişlikleri). |
| Süreç / dinamik kod | `Process`, `dlopen`, script çalıştırma yok. |
| Üçüncü parti bağımlılık | Yok. |
| Kullanıcı girdisi | Not metni düz metin olarak saklanır ve gösterilir; markdown/HTML yorumlanmaz, enjeksiyon yüzeyi yok. Önizleme regex'leri doğrusal (ReDoS yok). |
| Sürükle-bırak | Yük `folio.<tür>:<UUID>` biçiminde doğrulanır; başka uygulamalardan gelen metin yalnızca kullanıcının kendi notlarıyla eşleşebilir. |
| Günlükler | Yalnızca depo açma hataları (`OSLog`), not içeriği loglanmaz. |

### Dağıtım (DMG)

- Mach-O universal (arm64 + x86_64), **hardened runtime** açık.
- İzinler: yalnızca `com.apple.security.app-sandbox`. `get-task-allow` (hata ayıklama) yok.
- İkili dosyada yerel yol, kişisel bilgi ya da hata ayıklama bayrağı (`-seedSampleData`, yalnızca DEBUG) yok.
- Depo geçmişinde parola, anahtar ya da token yok; Apple Developer Team ID `Config/Local.xcconfig`'e (git dışı) taşındı.

### Bilinen sınırlamalar

1. **Notarize edilmemiş, ad-hoc imzalı.** Gatekeeper ilk açılışta uyarır; DMG'nin bütünlüğü yalnızca
   yayınlanan SHA-256 ile doğrulanabilir. Developer ID + notarization ile giderilir (`scripts/make-dmg.sh` destekler).
2. **Veriler şifrelenmemiş SQLite deposunda** (`~/Library/Containers/com.talha.folio`). Disk şifrelemesi için FileVault'a dayanır.
3. **Depo açılamazsa uygulama kapanır** (`fatalError`). Veri kaybına yol açmaz ama bozuk bir depo uygulamanın açılmasını engeller.
