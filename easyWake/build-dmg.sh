#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
RELEASE_DIR="$PROJECT_DIR/build/releases"
mkdir -p "$RELEASE_DIR"
STAGING="$(mktemp -d "$PROJECT_DIR/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/EasyWake.app"
DMG="$RELEASE_DIR/EasyWake-$VERSION-universal.dmg"

APP_OUTPUT_PATH="$APP" ARCHITECTURES="arm64 x86_64" bash "$PROJECT_DIR/build.sh"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Installation.txt" <<'EOF'
EASYWAKE

Installation
Glissez EasyWake.app sur le dossier Applications, puis éjectez ce disque.
Lancez ensuite EasyWake depuis Applications.

Compatible avec les Mac Apple Silicon et Intel sous macOS 13 ou ultérieur.

Utilisation
Activez EasyWake pour maintenir le Mac et son écran éveillés.
Pour simuler les mouvements de souris, autorisez EasyWake dans Réglages
Système > Confidentialité et sécurité > Accessibilité.

L'option « Lancer au démarrage » ouvre l'application à votre connexion.
Fermer la fenêtre masque l'icône du Dock ; le soleil dans la barre de
menus permet de rouvrir la fenêtre ou d'arrêter l'application.

Version de préparation
Ce DMG n'est ni signé avec un certificat Developer ID ni notarisé.
L'application possède uniquement une signature ad hoc de compilation.
La signature de distribution et la notarisation seront ajoutées plus tard.
EOF

/usr/bin/hdiutil create -volname "EasyWake $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -ov "$DMG"
/usr/bin/hdiutil verify "$DMG"
(cd "$RELEASE_DIR" && /usr/bin/shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf 'DMG créé : %s\n' "$DMG"
