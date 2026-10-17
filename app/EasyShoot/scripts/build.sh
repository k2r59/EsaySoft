#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --arch arm64 --arch x86_64
mkdir -p dist/EasyShoot.app/Contents/MacOS
mkdir -p dist/EasyShoot.app/Contents/Resources
swift scripts/generate-icon.swift .build/EasyShoot.iconset
iconutil -c icns .build/EasyShoot.iconset -o dist/EasyShoot.app/Contents/Resources/EasyShoot.icns
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
cp "$binary_dir/EasyShoot" dist/EasyShoot.app/Contents/MacOS/EasyShoot
cp LICENSE dist/EasyShoot.app/Contents/Resources/LICENSE.txt
cat > dist/EasyShoot.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>EasyShoot</string>
<key>CFBundleExecutable</key><string>EasyShoot</string>
<key>CFBundleIdentifier</key><string>local.easyshoot.app</string>
<key>CFBundleName</key><string>EasyShoot</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Image et vidéo</string>
<key>CFBundleTypeRole</key><string>Editor</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.image</string><string>public.movie</string></array>
</dict></array>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 EasyShoot contributors. MIT License.</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>EasyShoot capture les zones et fenêtres que vous choisissez, et enregistre votre écran sur demande.</string>
</dict></plist>
PLIST
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" dist/EasyShoot.app
else
  codesign --force --sign - dist/EasyShoot.app
fi
codesign --verify --strict dist/EasyShoot.app
lipo dist/EasyShoot.app/Contents/MacOS/EasyShoot -verify_arch arm64
lipo dist/EasyShoot.app/Contents/MacOS/EasyShoot -verify_arch x86_64
printf 'Application créée : %s/dist/EasyShoot.app\n' "$PWD"
