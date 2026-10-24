#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Preserve the deployment target while declaring the SDK actually used. Some
# Swift Build versions otherwise stamp the minimum OS as the SDK, enabling
# legacy AppKit rendering even when native Liquid Glass APIs are available.
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
link_sdk=(-Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$sdk_version")
swift build -j 2 -c release --arch arm64 --arch x86_64 "${link_sdk[@]}"
app=${APP_BUNDLE_PATH:-dist/EasyPaste.app}
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
sparkle=.build/artifacts/sparkle/Sparkle
ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
swift scripts/generate-icon.swift .build/EasyPaste.iconset
rm -f .build/EasyPaste.icns
iconutil -c icns .build/EasyPaste.iconset -o .build/EasyPaste.icns
cp .build/EasyPaste.icns "$app/Contents/Resources/EasyPaste.icns"
binary_dir=$(swift build -j 2 -c release --arch arm64 --arch x86_64 "${link_sdk[@]}" --show-bin-path)
cp "$binary_dir/EasyPaste" "$app/Contents/MacOS/EasyPaste"
mkdir -p "$app/Contents/Resources/BrowserExtension"
for item in manifest.json popup.html popup.css popup.js src icons LICENSE; do
    ditto "BrowserExtension/$item" "$app/Contents/Resources/BrowserExtension/$item"
done
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/THIRD-PARTY-NOTICES.md"
cp Sources/CArgon2/LICENSE "$app/Contents/Resources/Argon2-LICENSE.txt"
cp Sources/EasyPaste/Resources/easypaste-ribbon.png "$app/Contents/Resources/easypaste-ribbon.png"
cp Sources/EasyPaste/Resources/easypaste-ribbon-mark.png "$app/Contents/Resources/easypaste-ribbon-mark.png"
cp Sources/EasyPaste/Resources/clipboard-studio.png "$app/Contents/Resources/clipboard-studio.png"
cp Sources/EasyPaste/Resources/feedback-*.wav "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EasyPaste</string>
<key>CFBundleName</key><string>EasyPaste</string>
<key>CFBundleIdentifier</key><string>app.easypaste.mac</string>
<key>CFBundleIconFile</key><string>EasyPaste</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.11</string>
<key>CFBundleVersion</key><string>16</string>
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
python3 - "$app/Contents/Info.plist" <<'PY'
import json, os, plistlib, sys
config = json.load(open("scripts/release.json"))
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
info.update(CFBundleShortVersionString=os.environ.get("EASYPASTE_TEST_VERSION", config["version"]),
            CFBundleVersion=os.environ.get("EASYPASTE_TEST_BUILD", config["build"]),
            SUFeedURL=config["feed"], SUPublicEDKey=config["publicKey"],
            SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
            SUSendProfileInfo=False, SUScheduledCheckInterval=86400,
            SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True)
with open(sys.argv[1], "wb") as target:
    plistlib.dump(info, target)
PY
framework="$app/Contents/Frameworks/Sparkle.framework"
# Sign nested services from the inside out; preserve the downloader's sandbox.
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
 codesign --force --entitlements scripts/EasyPaste.entitlements --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
else
 codesign --force --entitlements scripts/EasyPaste.entitlements --sign - "$app"
fi
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/EasyPaste" -verify_arch arm64
lipo "$app/Contents/MacOS/EasyPaste" -verify_arch x86_64
print "Application : $PWD/$app"
