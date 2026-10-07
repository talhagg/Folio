#!/bin/zsh
# Folio.app'i Release olarak derler, imzalar ve dist/Folio-<sürüm>.dmg üretir.
#
# Varsayılan: ad-hoc imza (Developer ID yok). Bu durumda uygulama notarize edilemez;
# ilk açılışta Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç" gerekir.
# Developer ID varsa: SIGN_IDENTITY="Developer ID Application: …" ./scripts/make-dmg.sh
# ardından: xcrun notarytool submit dist/Folio-*.dmg --keychain-profile <profil> --wait
#           xcrun stapler staple dist/Folio-*.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

SIGN_IDENTITY=${SIGN_IDENTITY:--}
DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Folio-release"
ENTITLEMENTS="Folio/Folio-Distribution.entitlements"

xcodebuild -scheme Folio -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  build | grep -E "error:|warning:|\*\* " || true

APP="$DERIVED/Build/Products/Release/Folio.app"
[[ -d "$APP" ]] || { echo "Derleme başarısız"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# Hardened runtime + dağıtım izinleriyle yeniden imzala (Xcode ad-hoc imzada hardened runtime'ı kapatır).
codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Folio.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
DMG="dist/Folio-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Folio $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
[[ "$SIGN_IDENTITY" != "-" ]] && codesign --sign "$SIGN_IDENTITY" "$DMG"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Hazır: $DMG"
