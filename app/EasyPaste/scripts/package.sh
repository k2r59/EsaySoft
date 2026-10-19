#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -n "${NOTARY_PROFILE:-}" && -z "${CODE_SIGN_IDENTITY:-}" ]]; then
 print -u2 'La notarisation nécessite CODE_SIGN_IDENTITY.'
 exit 1
fi
./scripts/build.sh
staging=$(mktemp -d "${TMPDIR:-/tmp}/EasyPaste-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto dist/EasyPaste.app "$staging/EasyPaste.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/Licence MIT.txt"
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
dmg=dist/EasyPaste-0.2.7-universal.dmg
hdiutil create -volname EasyPaste -srcfolder "$staging" -format UDZO -fs HFS+ -ov "$dmg"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
 codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$dmg"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
 xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
 xcrun stapler staple "$dmg"
 xcrun stapler validate "$dmg"
 xcrun stapler staple dist/EasyPaste.app
 spctl --assess --type execute --verbose=2 dist/EasyPaste.app
 spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
ditto -c -k --sequesterRsrc --keepParent dist/EasyPaste.app dist/EasyPaste-0.2.7-universal.zip
mkdir -p "$staging/EasyPaste-source"
cp Package.swift LICENSE README.md QA-0.2.2.md QA-0.2.3.md QA-0.2.4.md QA-0.2.5.md QA-0.2.6.md QA-0.2.7.md ASSET-PROMPT.txt .gitignore "$staging/EasyPaste-source/"
ditto Sources "$staging/EasyPaste-source/Sources"
ditto Tests "$staging/EasyPaste-source/Tests"
ditto scripts "$staging/EasyPaste-source/scripts"
ditto -c -k --keepParent "$staging/EasyPaste-source" dist/EasyPaste-0.2.7-source.zip
(cd dist && shasum -a 256 EasyPaste-0.2.7-universal.dmg EasyPaste-0.2.7-universal.zip EasyPaste-0.2.7-source.zip) > dist/SHA256SUMS
print "Installateur : $PWD/$dmg"
