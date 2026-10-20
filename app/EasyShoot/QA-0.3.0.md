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

## Parcours graphiques vérifiés

- Sauvegarde de la version personnelle 0.2.2, puis installation de la version de départ signée/notarisée 0.3.0-rc build 4 dans Applications. Recherche native Sparkle → téléchargement du DMG public → « Install and Relaunch » → installation 0.3.0 build 5. Relance automatique confirmée par le changement de PID, avant toute requête de l’outil UI susceptible de lancer l’application.
- Nouvelle recherche depuis 0.3.0 : dialogue français « Votre logiciel est à jour ». Signature Developer ID et acceptation Gatekeeper vérifiées après l’installation.
- Réglages : clic dans l’espace vide de la ligne du son, puis rétablissement du réglage ; clic dans la marge de l’onglet Mises à jour. Les surfaces complètes répondent. Les sons restent activés, les vérifications automatiques restent désactivées.
- Sélection et export défilant réels dans Safari, sur l’écran LG UltraFine Retina, avec la page locale `scripts/scroll-fixture.html` : trois portions assemblées sur fond clair, PNG de 1490 × 3900 pixels ; trois portions sur fond sombre, PNG de 1490 × 3628 pixels. Pause, défilement pendant la pause, reprise et export vérifiés.
- Les deux exports ont été inspectés visuellement. Vision reconnaît les titres 01 à 09 dans l’ordre sur chacun ; l’analyse des pixels ne trouve aucune ligne entièrement noire. Les portions restent continues et les commandes d’EasyShoot ne figurent pas dans les images. Le pointeur avec halo de l’outil de contrôle est visible par endroits dans ces seules mires de test.
- La copie de l’image claire conserve 1490 × 3900 pixels dans le presse-papiers, sans réduction. Une sélection annulée avec Échap n’a créé aucun fichier.
- Les 14 captures personnelles préexistantes sont encore identiques par SHA-256 après les essais. Deux captures de contrôle ont été ajoutées à la bibliothèque.
- Observation ponctuelle du processus : environ 100 Mio résidents pendant l’assemblage ; environ 74 Mio et 0 % CPU après l’export. Ce relevé local n’est pas un benchmark sur les autres Macs. Aucun nouveau rapport de crash EasyShoot trouvé.

Les essais locaux autorisent la publication stable. Le signalement de Thierry devra néanmoins être confirmé sur sa page et son Mac ; ces tests ne prouvent pas que tous les contenus ou toutes les configurations sont capturables.

