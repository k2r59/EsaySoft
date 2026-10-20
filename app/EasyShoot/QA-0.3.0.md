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

## Distribution et mise à jour vérifiées

- Application universelle 0.3.0, build 5. Déploiement minimal du Mach-O : macOS 15.0. Signature Developer ID « Les papas du code » ; Gatekeeper accepte l’application et le DMG.
- Notarisation finale acceptée : `4ee89284-9fe4-4dd6-b875-5781095f9edf`.
- Flux HTTPS public comparé octet par octet au flux signé local. Le flux EasyPaste est resté inchangé.
- Signatures du flux et du DMG valides ; la modification d’un seul octet fait échouer la vérification de chacun.
- Cycle réel via le pilote officiel Sparkle CLI 2.10.0, compilé depuis le checkout épinglé et lié au même framework que l’application : copie isolée signée/notarisée 0.3.0-rc build 4 → téléchargement GitHub → vérification → extraction → installation 0.3.0 build 5. « Installation Finished », code de sortie 0, signature et Gatekeeper valides après installation. L’application personnelle n’a pas été remplacée durant ce test.
- Vérification suivante : aucune mise à jour supplémentaire disponible.
- 14 captures personnelles préexistantes comparées par SHA-256 avant/après : toutes identiques.
- Sons PCM chargés et joués avec le lecteur macOS ; aucun fichier sonore externe.

Les parcours graphiques (capture défilante sur une vraie page, marges cliquables des réglages, installation et relance dans l’application personnelle) restent à vérifier dès que le clavier et la souris sont disponibles. La release reste en préversion et la PR en brouillon jusque-là.

