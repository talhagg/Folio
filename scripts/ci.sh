#!/bin/zsh
# Komut satırı doğrulaması: provisioning profili olmadan ad-hoc imzayla derler ve testleri çalıştırır.
# iCloud entitlement'ları bu modda kapalıdır; uygulama yerel depoya düşer.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
action=${1:-test}
xcodebuild -scheme Folio -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Folio-ci" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  CODE_SIGN_ENTITLEMENTS= \
  "$action"
