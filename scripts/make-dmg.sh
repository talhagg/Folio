#!/bin/zsh
# Folio'yu Release olarak derler, imzalar ve dist/Folio-<sürüm>.dmg üretir.
#
# İki mod, Keychain'e göre otomatik seçilir:
#  • Developer ID — "Developer ID Application" sertifikası varsa: Xcode arşivi + Developer ID dışa aktarımı
#    (iCloud senkronu dahil), DMG imzası, notarization ve staple. Notarization için bir kez:
#      xcrun notarytool store-credentials folio-notary --apple-id <e-posta> --team-id <TEAM_ID>
#  • Ad-hoc — sertifika yoksa: iCloud'suz, yalnızca sandbox; ilk açılışta "Yine de Aç" gerekir.
#
# Ortam değişkenleri: NOTARY_PROFILE (varsayılan folio-notary), FORCE_ADHOC=1.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

NOTARY_PROFILE=${NOTARY_PROFILE:-folio-notary}
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Folio-release"
TEAM_ID=$(sed -nE 's/^DEVELOPMENT_TEAM *= *([A-Z0-9]+).*/\1/p' Config/Local.xcconfig 2>/dev/null || true)
DEVELOPER_ID=$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)

if [[ -n "$DEVELOPER_ID" && -n "$TEAM_ID" && -z "${FORCE_ADHOC:-}" ]]; then
  MODE=developer-id
else
  MODE=adhoc
fi
echo "Mod: $MODE ${DEVELOPER_ID:+($DEVELOPER_ID)}"

rm -rf "$DERIVED/export"
if [[ $MODE == developer-id ]]; then
  ARCHIVE="$DERIVED/Folio.xcarchive"
  xcodebuild archive -project Folio.xcodeproj -scheme Folio -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
    | grep -E "error:|warning:|\*\* " || true

  OPTIONS=$(mktemp -t ExportOptions).plist
  cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>iCloudContainerEnvironment</key><string>Production</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
    -exportPath "$DERIVED/export" -allowProvisioningUpdates | grep -E "error:|\*\* " || true
  APP="$DERIVED/export/Folio.app"
else
  ENTITLEMENTS="Folio/Folio-Distribution.entitlements"
  xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" build | grep -E "error:|warning:|\*\* " || true
  APP="$DERIVED/Build/Products/Release/Folio.app"
  # Xcode ad-hoc imzada hardened runtime'ı kapatır; yeniden imzala.
  codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi

[[ -d "$APP" ]] || { echo "Derleme ya da dışa aktarım başarısız"; exit 1; }
codesign --verify --strict --verbose=2 "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Folio.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
DMG="dist/Folio-$VERSION.dmg"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Folio $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ $MODE == developer-id ]]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -vv "$DMG"
  else
    echo "UYARI: '$NOTARY_PROFILE' notarization profili yok; DMG imzalı ama notarize edilmedi."
  fi
fi

# Yalnızca dosya adı: indirilen klasörde `shasum -c` çalışsın.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"
echo "Hazır: $DMG"
