#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -j 2 -c release --arch arm64 --arch x86_64
app=${APP_BUNDLE_PATH:-dist/EasyShoot.app}
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
sparkle=.build/artifacts/sparkle/Sparkle
ditto "$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
swift scripts/generate-icon.swift .build/EasyShoot.iconset
rm -f .build/EasyShoot.icns
iconutil -c icns .build/EasyShoot.iconset -o .build/EasyShoot.icns
cp .build/EasyShoot.icns "$app/Contents/Resources/EasyShoot.icns"
binary_dir=$(swift build -j 2 -c release --arch arm64 --arch x86_64 --show-bin-path)
cp "$binary_dir/EasyShoot" "$app/Contents/MacOS/EasyShoot"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/THIRD-PARTY-NOTICES.md"
cp Sources/EasyShoot/Resources/feedback-*.wav "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
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
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>CFBundleLocalizations</key><array><string>fr</string></array>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>EasyShoot capture les zones et fenêtres que vous choisissez, et enregistre votre écran sur demande.</string>
</dict></plist>
PLIST
python3 - "$app/Contents/Info.plist" <<'PY'
import json, os, plistlib, sys
config = json.load(open("scripts/release.json"))
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
info.update(CFBundleShortVersionString=os.environ.get("EASYSHOOT_TEST_VERSION", config["version"]),
            CFBundleVersion=os.environ.get("EASYSHOOT_TEST_BUILD", config["build"]),
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
 codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$app"
else
 codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/EasyShoot" -verify_arch arm64
lipo "$app/Contents/MacOS/EasyShoot" -verify_arch x86_64
print "Application : $PWD/$app"
