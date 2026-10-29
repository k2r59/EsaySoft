#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(python3 -c 'import json; print(json.load(open("scripts/release.json"))["version"])')
export APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-dist/EasyMusic-$VERSION.app}"
export BUNDLE_RUNTIME=1
./scripts/build-app.sh
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP_BUNDLE_PATH" "$STAGING/EasyMusic.app"
ln -s /Applications "$STAGING/Applications"
cp THIRD-PARTY-NOTICES.md EsaySoft-LICENSE.txt "$STAGING/"
echo 'Glissez EasyMusic dans Applications, puis ouvrez-la. macOS 13 ou ultérieur, Intel et Apple Silicon.' > "$STAGING/Installation.txt"
DMG="dist/EasyMusic-$VERSION-universal.dmg"
hdiutil create -volname EasyMusic -srcfolder "$STAGING" -format UDZO -fs HFS+ -ov "$DMG"
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG"; fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  xcrun stapler staple "$APP_BUNDLE_PATH"
  spctl --assess --type execute "$APP_BUNDLE_PATH"
fi
ditto "$APP_BUNDLE_PATH" "$STAGING/EasyMusic.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/EasyMusic.app" "dist/EasyMusic-$VERSION-universal.zip"
python3 scripts/package-source.py "dist/EasyMusic-$VERSION-source.zip"
(cd dist && shasum -a 256 "EasyMusic-$VERSION-universal.dmg" "EasyMusic-$VERSION-universal.zip" "EasyMusic-$VERSION-source.zip") > dist/SHA256SUMS
echo "Paquet créé : $DMG"
