#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -n "${NOTARY_PROFILE:-}" && -z "${CODE_SIGN_IDENTITY:-}" ]]; then
 print -u2 'La notarisation nécessite CODE_SIGN_IDENTITY.'
 exit 1
fi
./scripts/build.sh
staging=$(mktemp -d "${TMPDIR:-/tmp}/EasyTile-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto dist/EasyTile.app "$staging/EasyTile.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/Licence MIT.txt"
cat > "$staging/Installation.txt" <<'TEXT'
EASYTILE

1. Glisse EasyTile dans Applications.
2. Ouvre EasyTile depuis Applications.
3. Clique sur Autoriser EasyTile, puis active EasyTile dans Accessibilité.
4. Reviens dans une application et ouvre la palette avec Ctrl + Option + Espace.

macOS 15 ou ultérieur. Mac Intel et Apple Silicon.
Code source sous licence MIT.
TEXT
dmg=dist/EasyTile-1.1.0-universal.dmg
hdiutil create -volname EasyTile -srcfolder "$staging" -format UDZO -fs HFS+ -ov "$dmg"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$dmg"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
 xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
 xcrun stapler staple "$dmg"
 xcrun stapler validate "$dmg"
 xcrun stapler staple dist/EasyTile.app
 spctl --assess --type execute --verbose=2 dist/EasyTile.app
 spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
ditto -c -k --sequesterRsrc --keepParent dist/EasyTile.app dist/EasyTile-1.1.0-universal.zip
mkdir -p "$staging/EasyTile-source"
cp Package.swift LICENSE README.md .gitignore "$staging/EasyTile-source/"
ditto Sources "$staging/EasyTile-source/Sources"
ditto Tests "$staging/EasyTile-source/Tests"
ditto scripts "$staging/EasyTile-source/scripts"
ditto -c -k --keepParent "$staging/EasyTile-source" dist/EasyTile-1.1.0-source.zip
shasum -a 256 "$dmg" dist/EasyTile-1.1.0-universal.zip dist/EasyTile-1.1.0-source.zip > dist/SHA256SUMS
print "Installateur : $PWD/$dmg"
