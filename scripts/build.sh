#!/bin/bash
# Builds Tavra and signs it with one stable certificate, so macOS remembers its Accessibility
# permission from one build to the next. ./scripts/build.sh [Debug|Release] [xcodebuild settings]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
xcodebuild -project Tavra.xcodeproj -scheme Tavra -configuration "$CONFIG" -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" -quiet "${@:2}"
APP="build/Build/Products/$CONFIG/Tavra.app"
IDENTITY="${DEVELOPER_ID:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-certificate -c "Naqara Dev Code Signing" >/dev/null 2>&1; then
    IDENTITY="Naqara Dev Code Signing"
  else
    IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)"
  fi
fi
if [[ -z "$IDENTITY" ]]; then
  echo "! No signing certificate: macOS will forget the Accessibility permission on every build."
  exit 0
fi
codesign --force --sign "$IDENTITY" --timestamp=none --options runtime --entitlements Config/Tavra.entitlements "$APP" 2>/dev/null
codesign --verify --strict "$APP"
echo "✓ $APP, signed with \"$IDENTITY\""
