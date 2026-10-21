#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -j 2 -c release --arch arm64 --arch x86_64
app=${APP_BUNDLE_PATH:-dist/EasyTile.app}
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
sparkle=.build/artifacts/sparkle/Sparkle
ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
cp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/THIRD-PARTY-NOTICES.md"
swift scripts/generate-icon.swift .build/EasyTile.iconset
iconutil -c icns .build/EasyTile.iconset -o "$app/Contents/Resources/EasyTile.icns"
binary_dir=$(swift build -j 2 -c release --arch arm64 --arch x86_64 --show-bin-path)
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
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>CFBundleLocalizations</key><array><string>fr</string></array>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 EasyTile contributors. MIT License.</string>
</dict></plist>
PLIST
python3 - "$app/Contents/Info.plist" <<'PYINFO'
import json, os, plistlib, sys
config = json.load(open("scripts/release.json"))
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
info.update(CFBundleShortVersionString=os.environ.get("EASYTILE_TEST_VERSION", config["version"]),
            CFBundleVersion=os.environ.get("EASYTILE_TEST_BUILD", config["build"]),
            SUFeedURL=config["feed"], SUPublicEDKey=config["publicKey"],
            SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=True,
            SUSendProfileInfo=False, SUScheduledCheckInterval=86400,
            SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True)
with open(sys.argv[1], "wb") as target:
    plistlib.dump(info, target)
PYINFO
framework="$app/Contents/Frameworks/Sparkle.framework"
sign_args=(--force --sign "${CODE_SIGN_IDENTITY:--}")
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 sign_args+=(--options runtime --timestamp)
fi
codesign "${sign_args[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
codesign "${sign_args[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${sign_args[@]}" "$framework/Versions/B/Autoupdate"
codesign "${sign_args[@]}" "$framework/Versions/B/Updater.app"
codesign "${sign_args[@]}" "$framework"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
else
 codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/EasyTile" -verify_arch arm64
lipo "$app/Contents/MacOS/EasyTile" -verify_arch x86_64
print "Application : $PWD/$app"
