#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tools
python3 scripts/prepare-ytdlp.py
if [ ! -f .tools/AppIcon.icns ]; then
  mkdir -p .tools/AppIcon.iconset
  swift scripts/make-icon.swift .tools/icon.png
  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" .tools/icon.png --out ".tools/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" .tools/icon.png --out ".tools/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns .tools/AppIcon.iconset -o .tools/AppIcon.icns
fi
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
DESTINATION="${APP_BUNDLE_PATH:-dist/EasyMusic.app}"
STAGING=$(mktemp -d "$PWD/.tools/build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/EasyMusic.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Frameworks"
cp "$BIN_DIR/EasyMusic" "$APP/Contents/MacOS/EasyMusic"
ditto .tools/runtime/yt-dlp-runtime "$APP/Contents/Resources/bin/yt-dlp-runtime"
cp .tools/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EasyMusic</string>
<key>CFBundleIdentifier</key><string>local.easymusic.app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>EasyMusic</string>
<key>CFBundleDisplayName</key><string>EasyMusic</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
SPARKLE=.build/artifacts/sparkle/Sparkle
 ditto "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
 cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
if [ "${BUNDLE_RUNTIME:-0}" = "1" ]; then
  ./scripts/build-dependencies.sh
  for TOOL in ffmpeg ffprobe node; do cp ".tools/runtime/$TOOL" "$APP/Contents/Resources/bin/$TOOL"; done
  mkdir -p "$APP/Contents/Resources/Licenses"
  cp .tools/vendor/yt-dlp-THIRD-PARTY-LICENSES.txt "$APP/Contents/Resources/Licenses/yt-dlp.txt"
  cp EsaySoft-LICENSE.txt "$APP/Contents/Resources/Licenses/"
  cp .tools/vendor/FFmpeg-n8.1.2/COPYING.LGPLv2.1 "$APP/Contents/Resources/Licenses/FFmpeg-LGPL.txt"
  cp .tools/vendor/lame-3.100/COPYING "$APP/Contents/Resources/Licenses/LAME-LGPL.txt"
  cp .tools/vendor/node-v22.23.4-darwin-arm64/LICENSE "$APP/Contents/Resources/Licenses/Node-LICENSE.txt"
fi
python3 - "$APP/Contents/Info.plist" <<'PYINFO'
import json,plistlib,sys
p=sys.argv[1]; c=json.load(open('scripts/release.json'))
d=plistlib.load(open(p,'rb'))
d.update(CFBundleShortVersionString=c['version'],CFBundleVersion=c['build'],CFBundleDevelopmentRegion='fr',CFBundleLocalizations=['fr'],
 SUFeedURL=c['feed'],SUPublicEDKey=c['publicKey'],SURequireSignedFeed=True,SUVerifyUpdateBeforeExtraction=True,
 SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False,SUAllowsAutomaticUpdates=False,SUSendProfileInfo=False,SUScheduledCheckInterval=86400)
plistlib.dump(d,open(p,'wb'))
PYINFO
SIGN=(--force --sign "${CODE_SIGN_IDENTITY:--}")
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then SIGN+=(--options runtime --timestamp); fi
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
codesign "${SIGN[@]}" "$FW/Versions/B/Updater.app"
codesign "${SIGN[@]}" "$FW"
python3 scripts/sign-ytdlp.py "$APP/Contents/Resources/bin/yt-dlp-runtime"
for TOOL in "$APP/Contents/Resources/bin/"*; do
 [ -f "$TOOL" ] || continue
 case "$(basename "$TOOL")" in
   node) codesign "${SIGN[@]}" --entitlements scripts/node.entitlements "$TOOL" ;;
   *) codesign "${SIGN[@]}" "$TOOL" ;;
 esac
done
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
python3 - "$APP/Contents/MacOS/EasyMusic" <<'PYARCH'
import subprocess,sys
arches=subprocess.check_output(['lipo','-archs',sys.argv[1]],text=True).split()
assert {'arm64','x86_64'}.issubset(arches), arches
PYARCH
mkdir -p "$(dirname "$DESTINATION")"
if [ -e "$DESTINATION" ]; then mv "$DESTINATION" ".tools/previous-app-$(date +%s).app"; fi
mv "$APP" "$DESTINATION"
echo "Application créée : $DESTINATION"
