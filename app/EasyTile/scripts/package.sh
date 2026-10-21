#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -n "${NOTARY_PROFILE:-}" && -z "${CODE_SIGN_IDENTITY:-}" ]]; then
 print -u2 'La notarisation nécessite CODE_SIGN_IDENTITY.'
 exit 1
fi
./scripts/build.sh
version=$(python3 -c 'import json; print(json.load(open("scripts/release.json"))["version"])')
app=${APP_BUNDLE_PATH:-dist/EasyTile.app}
staging=$(mktemp -d "${TMPDIR:-/tmp}/EasyTile-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/EasyTile.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/Licence MIT.txt"
cp THIRD-PARTY-NOTICES.md "$staging/Composants tiers.md"
cat > "$staging/Installation.txt" <<'TEXT'
EASYSHOOT

1. Glisse EasyTile dans Applications.
2. Ouvre EasyTile depuis Applications.
3. Autorise EasyTile dans Accessibilité si nécessaire.
4. Pour les prochaines versions : menu EasyTile → Rechercher des mises à jour…

macOS 15 ou ultérieur. Mac Intel et Apple Silicon.
Dispositions et préférences sur le Mac. Code source MIT ; Sparkle sous ses licences propres.

TEXT
dmg="dist/EasyTile-$version-universal.dmg"
hdiutil create -volname EasyTile -srcfolder "$staging" -format UDZO -fs HFS+ -ov "$dmg"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$dmg"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
 xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
 xcrun stapler staple "$dmg"
 xcrun stapler validate "$dmg"
 xcrun stapler staple "$app"
 spctl --assess --type execute --verbose=2 "$app"
 spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
ditto "$app" "$staging/EasyTile.app"
ditto -c -k --sequesterRsrc --keepParent "$staging/EasyTile.app" "dist/EasyTile-$version-universal.zip"
mkdir -p "$staging/EasyTile-source"
cp Package.swift Package.resolved LICENSE README.md QA-*.md THIRD-PARTY-NOTICES.md .gitignore "$staging/EasyTile-source/"
ditto Sources "$staging/EasyTile-source/Sources"
ditto Tests "$staging/EasyTile-source/Tests"
ditto scripts "$staging/EasyTile-source/scripts"
ditto docs "$staging/EasyTile-source/docs"
ditto -c -k --keepParent "$staging/EasyTile-source" "dist/EasyTile-$version-source.zip"
(cd dist && shasum -a 256 "EasyTile-$version-universal.dmg" "EasyTile-$version-universal.zip" "EasyTile-$version-source.zip") > dist/SHA256SUMS
print "Installateur : $PWD/$dmg"
