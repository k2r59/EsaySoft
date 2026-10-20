# Contrôles EasyShoot 0.3.0 — 20 octobre 2026

## Automatisés

- 19 tests XCTest : configuration Retina, régions invalides, images noires/transparence, conservation des portions valides, annulation, raccords au pixel près, sons, reports d’installation et blocage des mises à jour pendant une opération.
- 33 contrôles de session défilante et de montage vidéo : raccords 1×/2×, doublons, saut sans recouvrement, refus d’autorisation, reprise, export PNG, durée/orientation/cadrage/audio des MP4.
- 19 contrôles de sélection, miniatures, stockage et libération des fenêtres.
- 6 tests d’intégration MCP, dont OCR local et refus de lecture hors des dossiers autorisés. Le test préalable vérifie aussi 5 assertions d’export/annotation/OCR.
- Les miniatures sont bornées à 620 × 360 ; le PNG conserve tous les pixels. La stabilité utilise de petites images, le raccord précis ne se lance qu’après stabilisation.

## Limites de validation

La cause exacte du problème observé sur le Mac de Thierry ne peut être confirmée sans sa capture et sa configuration. Les nouvelles protections couvrent les images noires entières, le retour de capture temporairement vide, les commandes flottantes, la résolution Retina et les changements d’écran. Un contenu protégé ne peut pas être capturé : l’app doit alors l’expliquer sans exporter silencieusement du noir.

Pas de test sur un Mac Intel physique ni sur toutes les versions de macOS. Les en-têtes fixes, animations, pages répétitives et grands sauts restent des limites du raccord vertical.

Les résultats des essais réels et de la notarisation sont ajoutés après leur exécution.
