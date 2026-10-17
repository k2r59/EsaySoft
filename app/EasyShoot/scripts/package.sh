#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/EasyShoot.app/Contents/Info.plist)
staging=$(mktemp -d "${TMPDIR:-/tmp}/EasyShoot-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto dist/EasyShoot.app "$staging/EasyShoot.app"
ln -s /Applications "$staging/Applications"
cp LICENSE "$staging/Licence MIT.txt"
cat > "$staging/Installation.txt" <<'TEXT'
INSTALLER EASYSHOOT

1. Glisse EasyShoot.app dans le dossier Applications.
2. Ouvre EasyShoot depuis Applications.
3. Autorise l’enregistrement de l’écran quand macOS le demande.

Compatible avec les Mac Intel et Apple Silicon sous macOS 15 ou plus récent.
Les captures et l’OCR restent sur ton Mac.

Utilise la copie du dossier Applications pour conserver une identité stable
lors des demandes d’autorisation macOS.

Code source sous licence MIT. Consulte Licence MIT.txt.
TEXT
dmg="dist/EasyShoot-${version}-universal.dmg"
hdiutil create -volname EasyShoot -srcfolder "$staging" -format UDZO -fs HFS+ -ov "$dmg"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$dmg"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
    print -u2 'CODE_SIGN_IDENTITY est requis pour la notarisation.'
    exit 1
  fi
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  xcrun stapler staple dist/EasyShoot.app
  spctl --assess --type execute --verbose=2 dist/EasyShoot.app
fi
ditto -c -k --sequesterRsrc --keepParent dist/EasyShoot.app "dist/EasyShoot-${version}-universal.zip"
source_stage="$staging/EasyShoot-source"
mkdir -p "$source_stage"
cp Package.swift LICENSE README.md .gitignore "$source_stage/"
ditto Sources "$source_stage/Sources"
ditto scripts "$source_stage/scripts"
ditto -c -k --keepParent "$source_stage" "dist/EasyShoot-${version}-source.zip"
shasum -a 256 "$dmg" "dist/EasyShoot-${version}-universal.zip" "dist/EasyShoot-${version}-source.zip" > dist/SHA256SUMS
print "Distribution prête : $dmg"
