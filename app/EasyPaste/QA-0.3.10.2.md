# Validation EasyPaste 0.3.10.2

2 novembre 2026. Publication autorisée par Hervé après sa dernière confirmation « Ça défile maintenant entre les tuiles » sur 0.3.10.2-beta.1 (30). Version publique 0.3.10.2, build 31.

## Correctif et validation

- Surface native de réception sous les cartes : hitTest natif conservé, fond blanc à 1 % dessiné dans le dirtyRect. Les espaces transparents peuvent recevoir la molette ; les cartes gardent la priorité pour les clics.
- Le traitement des deltas et le routage de la fenêtre restent ceux de 0.3.10.1. Aucun moniteur global ou minuterie ajouté.
- **338 tests Release sans échec**, 54,070 s, SDK 27 déclaré explicitement ; journal local /tmp/easypaste-native-gap-full.log. Sept tests ciblés de défilement, réception native et priorité des clics, 18,508 s.
- Bêta validée construite avec scripts/build.sh, Intel et Apple Silicon, minimum macOS 15, SDK 27. La publication utilise ce même projet de construction interne et les mêmes sources fonctionnelles, avec un autre chemin de bundle pour ne pas modifier l’app de test en cours d’exécution.
- L’ancienne bêta issue de swift test déclarait SDK 15 : elle ne constituait pas une comparaison de construction identique à la production. Cette pratique est abandonnée.

## Limites et contrôles de livraison

Le geste réel a été validé par Hervé avec sa souris Logitech, pas avec tous les matériels possibles. Les événements générés par l’outil Computer Use avaient des deltas nuls dans cette session et ne sont pas présentés comme validation matérielle. Pas de nouvelle exécution sur Mac Intel ni de parcours caméra/micro/Bitwarden.

Contrôles avant annonce : identité des sources et du code machine avec la bêta validée, architecture/SDK, signature Developer ID, notarisation Apple, signatures Sparkle, téléchargement et empreintes des archives, flux public. Le contrôle du flux ne vaut pas une installation OTA complète. Résultats définitifs consignés dans le document de reprise.
