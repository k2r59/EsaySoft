#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Validate restricted entitlements before touching an existing build.
cloud_entitlements=".build/iCloud-distribution.entitlements"
mkdir -p .build
if [[ -n "${CLOUD_PROFILE:-}" ]]; then
 if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
  print -u2 'iCloud nécessite une identité Developer ID et un profil Apple.'
  exit 1
 fi
 python3 scripts/cloud-signing.py "$CLOUD_PROFILE" "$CODE_SIGN_IDENTITY" "$cloud_entitlements"
fi
swift build -j 2 -c release --arch arm64 --arch x86_64
app="${BUILD_APP_PATH:-dist/EasyPaste.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift scripts/generate-icon.swift .build/EasyPaste.iconset
iconutil -c icns .build/EasyPaste.iconset -o "$app/Contents/Resources/EasyPaste.icns"
binary_dir=$(swift build -j 2 -c release --arch arm64 --arch x86_64 --show-bin-path)
cp "$binary_dir/EasyPaste" "$app/Contents/MacOS/EasyPaste"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp Sources/EasyPaste/Resources/clipboard-studio.png "$app/Contents/Resources/clipboard-studio.png"
cp Configuration/Info.plist "$app/Contents/Info.plist"
entitlements=scripts/EasyPaste.entitlements
if [[ -n "${CLOUD_PROFILE:-}" ]]; then
 cp "$CLOUD_PROFILE" "$app/Contents/embedded.provisionprofile"
 entitlements="$cloud_entitlements"
else
 rm -f "$app/Contents/embedded.provisionprofile"
fi
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --entitlements "$entitlements" --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
else
 codesign --force --entitlements "$entitlements" --sign - "$app"
fi
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/EasyPaste" -verify_arch arm64
lipo "$app/Contents/MacOS/EasyPaste" -verify_arch x86_64
print "Application : $PWD/$app"
