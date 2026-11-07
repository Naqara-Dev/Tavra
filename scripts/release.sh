#!/bin/bash
# Builds a release: dist/Tavra-X.dmg, after the tests pass, for a GitHub release of Naqara-Dev/Tavra.
# Signed with the "Naqara Dev Code Signing" certificate, or DEVELOPER_ID if set. It isn't notarized, so
# macOS asks to confirm the first launch. Tavra doesn't use the network, so there's no update feed.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Tavra.xcodeproj/project.pbxproj | head -1)
DMG="dist/Tavra-$VERSION.dmg"
rm -rf dist && mkdir -p dist

echo "› Testing"
./scripts/test.sh
./scripts/build.sh Debug
./scripts/e2e.sh

echo "› Building Tavra $VERSION"
./scripts/build.sh Release ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64'
APP=build/Build/Products/Release/Tavra.app
echo "  Architectures: $(lipo -archs "$APP/Contents/MacOS/Tavra")"
if strings "$APP/Contents/MacOS/Tavra" | grep -qE "TavraFake|TAVRA_"; then
  echo "! Debug hooks in a release build"
  exit 1
fi

echo "› Creating $DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tavra" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"
echo "✓ $DMG"
shasum -a 256 "$DMG"
