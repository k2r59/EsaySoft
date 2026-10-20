# Publier une mise à jour EasyShoot

EasyShoot utilise Sparkle 2.10.0, un flux HTTPS signé et des DMG universels signés Developer ID et notarisés. Le code MIT et les licences Sparkle sont fournis dans la distribution.

- Configuration : `scripts/release.json`.
- Identifiant conservé : `local.easyshoot.app`.
- Flux : https://k2r59.github.io/EsaySoft/easyshoot/appcast.xml
- Clé privée Ed25519 : trousseau local, compte `local.easyshoot.app`. Ne jamais l’exporter dans le dépôt.
- Hébergement : releases du dépôt k2r59/EsaySoft et branche gh-pages. Le flux EasyPaste est conservé.

1. Augmenter la version et le build dans release.json, écrire les notes, exécuter les tests.
2. Construire dans un nouveau dossier, signer et notariser :

```sh
APP_BUNDLE_PATH=dist/EasyShoot-0.3.0.app \
CODE_SIGN_IDENTITY="Developer ID Application: VOTRE IDENTITÉ" \
NOTARY_PROFILE="VOTRE PROFIL" ./scripts/package.sh
```

3. Commiter et pousser les sources, puis publier :

```sh
python3 scripts/publish-update.py --notes docs/RELEASE-0.3.0.md --publish
```

Le script vérifie signatures, notarisation, numéros et sommes SHA-256 ; crée une release provisoire, retélécharge les fichiers pour comparaison, publie, puis avance le flux signé sans écraser une version existante. Vérifier ensuite le déploiement HTTPS et l’installation native Sparkle depuis un build inférieur. `EASYSHOOT_TEST_VERSION` / `EASYSHOOT_TEST_BUILD` servent uniquement aux exemplaires de test ; la publication refuse des métadonnées différentes de release.json.

Les vérifications automatiques sont désactivées par défaut, activables dans Réglages, au plus une fois par jour. Aucune télémétrie ni installation automatique. Les captures, OCR, sélections, éditions et enregistrements empêchent une mise à jour intrusive. Le processus MCP et les tests ne démarrent pas Sparkle.
