#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${APP_OUTPUT_PATH:-$PROJECT_DIR/build/EasyWake.app}"
ARCHITECTURES="${ARCHITECTURES:-$(uname -m)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ICONSET="$PROJECT_DIR/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$PROJECT_DIR/Assets/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  /usr/bin/sips -z "$retina_size" "$retina_size" "$PROJECT_DIR/Assets/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"
BINARIES=()
for arch in $ARCHITECTURES; do
  case "$arch" in
    arm64|x86_64) ;;
    *) printf 'Architecture non prise en charge : %s\n' "$arch" >&2; exit 1 ;;
  esac
  binary="$PROJECT_DIR/build/EasyWake-$arch"
  xcrun swiftc -O -target "$arch-apple-macosx13.0" \
    -framework AppKit -framework ApplicationServices -framework IOKit -framework ServiceManagement \
    "$PROJECT_DIR/Sources/main.swift" -o "$binary"
  BINARIES+=("$binary")
done
xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/EasyWake"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
printf 'Application créée : %s\n' "$APP"
