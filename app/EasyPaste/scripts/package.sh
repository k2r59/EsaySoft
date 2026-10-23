#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -n "${NOTARY_PROFILE:-}" && -z "${CODE_SIGN_IDENTITY:-}" ]]; then
 print -u2 'La notarisation nécessite CODE_SIGN_IDENTITY.'
 exit 1
fi
./scripts/build.sh
version=$(python3 -c 'import json; print(json.load(open("scripts/release.json"))["version"])')
app=${APP_BUNDLE_PATH:-dist/EasyPaste.app}
staging=$(mktemp -d "${TMPDIR:-/tmp}/EasyPaste-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/EasyPaste.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/Licence MIT.txt"
cp THIRD-PARTY-NOTICES.md "$staging/Composants tiers.md"
cp Sources/CArgon2/LICENSE "$staging/Argon2-LICENSE.txt"
cat > "$staging/Installation.txt" <<'TEXT'
EASYPASTE

1. Glisse EasyPaste dans Applications.
2. Ouvre EasyPaste depuis Applications.
3. Clique sur Activer l’historique, puis copie un texte ou une image.
4. Ouvre la barre rapide avec Maj + Commande + V.
5. Autorise le collage direct dans Réglages si tu le souhaites. Sinon, utilise Commande + V après avoir choisi un élément.

macOS 15 ou ultérieur. Mac Intel et Apple Silicon.
Code source sous licence MIT.
TEXT
dmg="dist/EasyPaste-$version-universal.dmg"
hdiutil create -volname EasyPaste -srcfolder "$staging" -format UDZO -fs HFS+ -ov "$dmg"
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
ditto "$app" "$staging/EasyPaste.app"
ditto -c -k --sequesterRsrc --keepParent "$staging/EasyPaste.app" "dist/EasyPaste-$version-universal.zip"
python3 scripts/package-source.py "dist/EasyPaste-$version-source.zip"
(cd dist && shasum -a 256 "EasyPaste-$version-universal.dmg" "EasyPaste-$version-universal.zip" "EasyPaste-$version-source.zip") > dist/SHA256SUMS
print "Installateur : $PWD/$dmg"
