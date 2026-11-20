# Composants tiers

Le code original d’EasyPaste reste sous licence MIT. Les composants ci-dessous
conservent leurs conditions propres.

## Sparkle

Les mises à jour utilisent Sparkle 2.10.0, sous licence MIT, avec ses composants
tiers sous licences BSD et zlib. Le framework est fourni par le projet officiel,
verrouillé par `Package.resolved` et la somme de contrôle du paquet Swift.

- Projet : https://github.com/sparkle-project/Sparkle
- Licences complètes : `Sparkle-LICENSE.txt` dans les ressources de l’application
  et `docs/Sparkle-LICENSE.txt` dans les sources.
- Le framework et ses services sont signés avec l’identité Developer ID d’EasyPaste.
- La licence MIT du code d’EasyPaste reste inchangée.

## Argon2

L’implémentation de référence C d’Argon2 est utilisée pour la connexion aux comptes
Bitwarden configurés avec Argon2id. Elle est embarquée statiquement, sans CLI.

- Projet : https://github.com/P-H-C/phc-winner-argon2
- Révision : `62358ba2123abd17fccf2a108a301d4b52c01a7c` (20190702).
- Auteurs : Daniel Dinu, Dmitry Khovratovich, Jean-Philippe Aumasson et Samuel Neves.
- Distribution originale : choix entre CC0 1.0 et Apache 2.0. EasyPaste utilise
  l’option CC0 1.0.
- Licence complète : `Sources/CArgon2/LICENSE` ; empreintes et provenance :
  `Sources/CArgon2/PROVENANCE.json`.
- Sources conservées à l’identique ; compilation de la version de référence,
  sans threads internes (`ARGON2_NO_THREADS`).

Aucun code du SDK interne ou des applications Bitwarden n’est embarqué.
L’implémentation de compatibilité utilise CommonCrypto, CryptoKit et Security
fournis par macOS. Bitwarden est une marque de Bitwarden Inc. Cette intégration
indépendante n’est ni fournie ni prise en charge par Bitwarden.

## Téléchargements web intégrés

Seuls les moteurs médias sont embarqués, pas l’application EasyMusic ni ses fonctions.
Ils sont exécutés comme programmes séparés et signés avec l’identité Developer ID
EasyPaste. Aucun outil n’est installé dans le système ou téléchargé au premier usage.

- yt-dlp 2026.10.26 : distribution autonome officielle avec Python et ses dépendances.
  https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26
  Licences tierces dans `Licenses/yt-dlp.txt` des ressources de l’application.
  Sa licence propre est dans `Licenses/yt-dlp-LICENSE.txt`. Sources de yt-dlp,
  Mutagen 1.48.1 (GPL-2.0-or-later) et certifi 2026.10.23 (MPL-2.0)
  incluses dans `.tools/vendor` de l’archive source.
- FFmpeg 8.1.2 et LAME 3.100 : LGPL 2.1 ou ultérieure. Les sources exactes
  non modifiées sont incluses dans `.tools/vendor` de l’archive source EasyPaste.
  La commande de compilation et toutes les options sont dans
  `scripts/build-media-dependencies.sh`. Aucun composant GPL/nonfree n’est activé.
  Licences dans `Licenses/FFmpeg-LGPL.txt` et `Licenses/LAME-LGPL.txt`.
  https://ffmpeg.org/legal.html
- Node.js 22.23.4 : MIT et licences tierces, reproduites dans
  `Licenses/Node-LICENSE.txt`. https://nodejs.org/dist/v22.23.4/

FFmpeg/LAME sont liés statiquement entre eux, pas à EasyPaste. Le script fourni
permet de reconstruire les exécutables complets, les modifier et les remplacer
avant de signer à nouveau votre build. Les dépendances sont verrouillées par
version et SHA-256 ; les signatures des composants natifs sont vérifiées au build.
