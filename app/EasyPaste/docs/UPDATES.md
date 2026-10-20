# Publier une mise à jour EasyPaste

EasyPaste utilise Sparkle 2.10.0. GitHub Releases héberge les DMG et la branche
`gh-pages` héberge le flux sur GitHub Pages. Aucun serveur applicatif n’est requis.
Les vérifications automatiques sont facultatives, désactivées au premier lancement
et espacées de 24 heures. Les téléchargements et installations restent manuels.

## Préparer

1. Augmenter `version` et **toujours** `build` dans `scripts/release.json`.
2. Rédiger les notes de version dans `docs/RELEASE-<version>.md`.
3. Exécuter `swift test -j 2 -c release`.
4. Construire dans un dossier neuf :

```sh
APP_BUNDLE_PATH=dist/EasyPaste-0.3.0.app \
CODE_SIGN_IDENTITY='Developer ID Application: Les papas du code (WN9MHL56A9)' \
NOTARY_PROFILE=EasyShoot ./scripts/package.sh
```

Adapter le numéro de version dans le chemin. `EasyShoot` est le nom historique
du profil de notarisation stocké dans le trousseau de ce Mac.

5. Vérifier l’app, puis commiter et pousser les sources. Aucun identifiant Apple,
clé privée, historique ou donnée Bitwarden ne doit entrer dans le dépôt.
6. Préparer le flux sans le publier :

```sh
python3 scripts/publish-update.py --notes docs/RELEASE-0.3.0.md
```

## Publier

```sh
python3 scripts/publish-update.py --notes docs/RELEASE-0.3.0.md --publish
```

Le script vérifie les signatures, la notarisation, les empreintes et la progression
du build. Il crée une release brouillon, téléverse les fichiers, les retélécharge
pour vérifier leur intégrité, publie la release, puis avance le flux signé.
Le flux n’annonce donc jamais une archive encore privée.

Le déploiement GitHub Pages prend un court délai. Vérifier ensuite que
`https://k2r59.github.io/EsaySoft/easypaste/appcast.xml` correspond octet pour octet
à `dist/appcast.xml`, et lancer « Rechercher des mises à jour… » dans l’app.

Ne jamais remplacer une archive déjà publiée ou modifier le XML signé à la main.
Si une publication échoue après la création d’une release, vérifier son état
avant toute reprise : le script refuse volontairement d’écraser une release.
Si seuls les fichiers du flux doivent être redéployés, réutiliser **le même**
`dist/appcast.xml` validé et la fonction `deploy` du script, sans le modifier.

## Clés et signatures

- Developer ID et notarisation : trousseau de ce Mac.
- Clé Ed25519 Sparkle : compte `app.easypaste.mac`, dans le trousseau.
- Seule la clé publique est dans `scripts/release.json` et dans l’application.
- Les flux et les archives sont signés ; la signature des archives est contrôlée
  avant leur extraction.
- Le DMG signé permet une rotation de clé conforme à la procédure Sparkle.
- Sauvegarder le trousseau en lieu sûr. Ne pas exporter une clé dans le dépôt.

Références : [Sparkle](https://sparkle-project.org/documentation/),
[publication](https://sparkle-project.org/documentation/publishing/).

## Essais

Les tests automatisés couvrent le report de l’installation et les activités qui
doivent la bloquer. Une validation réelle doit aussi installer une ancienne
version munie de Sparkle, déclencher la mise à jour, vérifier le redémarrage,
le numéro de build, la signature et la conservation de l’historique.

`EASYPASTE_TEST_VERSION` et `EASYPASTE_TEST_BUILD` permettent de construire un
point de départ de test. Ne jamais distribuer cette version. Le script de
publication rejette les numéros différents de `release.json`.
Les versions 0.2.11 et antérieures n’ayant pas Sparkle, leurs utilisateurs doivent
installer une fois le DMG 0.3.0 ou une version ultérieure.
