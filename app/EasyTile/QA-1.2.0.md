# Validation EasyTile 1.2.0

## Tests automatiques

`swift test -j 2 -c release` : **26 tests réussis**, aucune erreur.

- Géométrie des huit dispositions, écrans à coordonnées négatives, espacement et zones du menu de glissement.
- Persistance des dispositions, espacement et préférence de glissement.
- Apparence : clair par défaut, choix conservé, suivi de macOS sans override, fenêtres existantes et nouvelles, couleurs dynamiques AppKit/SwiftUI.
- Contraste d’au moins 4,5:1 pour les couleurs de texte et d’accent dans les deux thèmes.
- Rendu des trois pages, éditeur et deux palettes dans les deux thèmes ; vérification de largeur à la taille minimale.
- Ouverture au démarrage : activation, désactivation, idempotence, validation macOS en attente, erreurs, changement externe, événement de lancement à la connexion.
- Mises à jour : aucun réseau à la construction, protection de l’éditeur, palette, déplacement et placement ; reprise explicite et unique d’une installation différée.

Les tests utilisent des préférences isolées et un service de connexion simulé. Aucun changement de fenêtres utilisateur ni d’éléments de connexion dans les tests unitaires.

## Distribution

La validation de la signature Developer ID, de la notarisation, des deux architectures et du flux signé est effectuée par les scripts de distribution. Les essais interactifs de la version installée sont consignés après publication.
