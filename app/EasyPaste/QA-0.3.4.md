# Validation EasyPaste 0.3.4

21 octobre 2026, Apple Silicon, macOS 27.

## Changements

- La barre rapide colle sur un clic normal. Cmd/Maj-clic gardent la sélection multiple ; les cartes de la bibliothèque conservent leur clic de sélection et leur double-clic de collage.
- Une nouvelle copie sélectionne sa carte, y compris après dédoublonnage. Une copie masquée par les filtres reste en attente jusqu’à la réouverture ; une sélection explicite de l’utilisateur prend la priorité. Les copies issues de l’historique et les modifications de métadonnées ne réinitialisent pas la sélection.
- Le trait des flèches pleines se termine sous leur pointe ; les flèches très courtes n’ont plus de capuchon arrondi dépassant la pointe.
- Le refus d’Accessibilité ouvre une explication visible avec accès aux réglages, sans masquer le message dans une barre déjà fermée.

## Vérifications automatiques

- `swift test -c release -j 2` : **215 tests, zéro échec**, 27,20 s.
- Onze tests ajoutés : clic unique et absence de double collage, modificateurs de sélection, réouvertures répétées, nouvelle copie, dédoublonnage, copie cachée par une recherche, priorité de la navigation manuelle, copie depuis l’historique, rendu des flèches.
- Le contrôle raster couvre 8 directions × 3 épaisseurs, 9 flèches courtes, la longueur nulle et les trois styles de pointe. Aucun pixel significatif au-delà de la pointe pleine, avec tolérance d’anticrénelage de 1 pixel.
- La première exécution Debug a passé les nouveaux tests mais rencontré deux échecs de préparation : les tests SVG existants attendent le binaire Release. Après compilation universelle, la suite Release complète passe.
- Compilation universelle arm64/x86_64 ; les deux exécutables ciblent macOS 15.0. Exécution sur Intel et sur d’autres versions de macOS non vérifiée ici.

## Essais d’interface

Même identité d’application et même chemin `/Applications/EasyPaste.app`, avec coffre temporaire de démonstration séparé du coffre utilisateur.

- Clic dans la marge d’une ancienne carte : sélection et tentative de collage, sans second clic.
- Refus d’Accessibilité : dialogue attendu ; le bouton ouvre bien le panneau système correspondant. L’interrupteur EasyPaste y est désactivé.
- Navigation droite/gauche, retour à la bibliothèque puis réouverture : dernière carte conservée.
- Menu « … » d’une carte : menu ouvert sans déclencher le collage.
- Planche de contrôle générée par le véritable `AnnotationRenderer.draw` : pointes pleines et ouvertes, directions et épaisseurs différentes, inspection visuelle correcte.

**Limite :** le collage effectif dans TextEdit reste à vérifier après autorisation Accessibilité. Cette autorisation n’est pas accordée automatiquement. Les tests ne constituent pas une mesure de latence image par image.

## Distribution et données

- Compilation, tests et préparation des archives sur le disque interne, avec deux tâches de compilation au maximum.
- Developer ID : Les papas du code (WN9MHL56A9).
- Application et DMG notarisés et agrafés ; Gatekeeper accepte les deux avec `Notarized Developer ID`.
- Notarisation : `6fa80acb-cf06-4ee8-a4d5-65c5a828bb2b`.
- Installation locale de la version normale 0.3.4 / build 21, sans marqueurs Demo/UpdateQA. Copie de test supprimée.
- Les 262 fichiers préexistants du coffre sont identiques avant et après les essais (SHA-256, sans déchiffrement).
