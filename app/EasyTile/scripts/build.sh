#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --arch arm64 --arch x86_64
app=dist/EasyTile.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift scripts/generate-icon.swift .build/EasyTile.iconset
iconutil -c icns .build/EasyTile.iconset -o "$app/Contents/Resources/EasyTile.icns"
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
cp "$binary_dir/EasyTile" "$app/Contents/MacOS/EasyTile"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EasyTile</string>
<key>CFBundleName</key><string>EasyTile</string>
<key>CFBundleIdentifier</key><string>app.easytile.mac</string>
<key>CFBundleIconFile</key><string>EasyTile</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 EasyTile contributors. MIT License.</string>
</dict></plist>
PLIST
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
else
 codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
lipo "$app/Contents/MacOS/EasyTile" -verify_arch arm64
lipo "$app/Contents/MacOS/EasyTile" -verify_arch x86_64
print "Application : $PWD/$app"
