# Composants tiers

Le code original d’EasyPaste reste sous licence MIT. Les composants ci-dessous
conservent leurs conditions propres.

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
