# Publier une mise à jour EasyTile

EasyTile utilise Sparkle 2.10.0, un flux HTTPS signé et des DMG universels signés Developer ID et notarisés. Le code MIT et les licences Sparkle sont fournis dans la distribution.

- Configuration : `scripts/release.json`.
- Identifiant conservé : `app.easytile.mac`.
- Flux : https://k2r59.github.io/EsaySoft/easytile/appcast.xml
- Clé privée Ed25519 : trousseau local, compte `app.easytile.mac`. Ne jamais l’exporter dans le dépôt.
- Hébergement : releases du dépôt k2r59/EsaySoft et branche gh-pages. Les flux EasyPaste et EasyShoot sont conservés.

1. Augmenter la version et le build dans release.json, écrire les notes, exécuter les tests.
2. Construire dans un nouveau dossier, signer et notariser :

```sh
APP_BUNDLE_PATH=dist/EasyTile-1.2.0.app \
CODE_SIGN_IDENTITY="Developer ID Application: VOTRE IDENTITÉ" \
NOTARY_PROFILE="VOTRE PROFIL" ./scripts/package.sh
```

3. Commiter et pousser les sources, puis publier :

```sh
python3 scripts/publish-update.py --notes docs/RELEASE-1.2.0.md --publish
```

Le script vérifie signatures, notarisation, numéros et sommes SHA-256 ; crée une release provisoire, retélécharge les fichiers pour comparaison, publie, puis avance le flux signé sans écraser une version existante. Vérifier ensuite le déploiement HTTPS et l’installation native Sparkle depuis un build inférieur. `EASYTILE_TEST_VERSION` / `EASYTILE_TEST_BUILD` servent uniquement aux exemplaires de test ; la publication refuse des métadonnées différentes de release.json.

Les vérifications automatiques sont activées par défaut, une fois par jour. L’option « Télécharger et installer automatiquement », désactivée par défaut, prépare l’installation à la fermeture de l’app. Une installation immédiate peut aussi être demandée depuis la fenêtre Sparkle. Aucun profil système n’est transmis.

L’éditeur, la palette, un glissement ou un placement en cours empêchent une mise à jour intrusive. Si une relance a été différée, le bouton « Installer et relancer » permet de la reprendre explicitement. Le diagnostic de placement et les tests ne démarrent pas Sparkle.

Les versions 1.1.x ne possèdent pas encore ce mécanisme : installer une fois le DMG 1.2.0. Les prochaines versions sont proposées dans l’app. L’identifiant, l’équipe de signature et le chemin `/Applications/EasyTile.app` sont conservés pour maintenir l’autorisation Accessibilité.
