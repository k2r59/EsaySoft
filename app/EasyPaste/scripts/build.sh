#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -j 2 -c release --arch arm64 --arch x86_64
app=dist/EasyPaste.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift scripts/generate-icon.swift .build/EasyPaste.iconset
iconutil -c icns .build/EasyPaste.iconset -o "$app/Contents/Resources/EasyPaste.icns"
binary_dir=$(swift build -j 2 -c release --arch arm64 --arch x86_64 --show-bin-path)
cp "$binary_dir/EasyPaste" "$app/Contents/MacOS/EasyPaste"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp Sources/EasyPaste/Resources/clipboard-studio.png "$app/Contents/Resources/clipboard-studio.png"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EasyPaste</string>
<key>CFBundleName</key><string>EasyPaste</string>
<key>CFBundleIdentifier</key><string>app.easypaste.mac</string>
<key>CFBundleIconFile</key><string>EasyPaste</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.3</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>CFBundleLocalizations</key><array><string>fr</string></array>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>EasyPaste capture les zones, les fenêtres ou les vidéos que vous choisissez et extrait leur texte sur votre Mac.</string>
<key>NSCameraUsageDescription</key><string>EasyPaste inclut votre webcam dans la vidéo uniquement lorsque vous activez cette option.</string>
<key>NSMicrophoneUsageDescription</key><string>EasyPaste utilise le microphone uniquement lorsque vous activez cette option pour une vidéo.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 EasyPaste contributors. MIT License.</string>
</dict></plist>
PLIST
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --entitlements scripts/EasyPaste.entitlements --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
else
 codesign --force --entitlements scripts/EasyPaste.entitlements --sign - "$app"
fi
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/EasyPaste" -verify_arch arm64
lipo "$app/Contents/MacOS/EasyPaste" -verify_arch x86_64
print "Application : $PWD/$app"
