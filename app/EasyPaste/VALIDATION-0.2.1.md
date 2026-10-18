# Vérification des zones cliquables

Vérification du 18 octobre 2026, sur un Mac Apple Silicon. Les essais d’interface utilisent l’historique de démonstration, isolé des données personnelles.

## Défaut reproduit

Dans la version 0.2.0, cliquer dans la marge droite de « Favoris » ne change pas de vue. Cliquer sur son texte ouvre les favoris. Les boutons SwiftUI de style `plain` ne couvrent pas systématiquement les espaces transparents de leur libellé.

## Correction

`FullAreaButtonStyle` définit une zone rectangulaire sur la totalité du libellé, après son dimensionnement. Tous les boutons personnalisés auparavant en style `plain` utilisent ce style. `PasteButtonStyle` couvre aussi ses marges et conserve sa taille pendant l’appui. Les petites commandes possèdent une cible d’au moins 24 points lorsqu’elles sont isolées.

La revue du code couvre la bibliothèque, la barre rapide, les réglages, les éditeurs, les aperçus et les panneaux de capture. Les menus AppKit conservent leurs interactions natives. La correction conserve les actions natives des boutons, leurs raccourcis et leurs états désactivés. Elle n’ajoute ni minuterie, ni tâche en arrière-plan, ni geste concurrent.

## Clics réels vérifiés

| Surface | Vérification | Résultat |
| --- | --- | --- |
| Navigation | Marges de l’historique, des favoris, de la pile, des trois collections, de la corbeille et des réglages | Vue correspondante ouverte |
| Filtres | Marges de Tout, Images et Textes | Nombre et type de cartes attendus |
| Création de texte | Coin du bouton Créer un texte, annulation et enregistrement | Ouverture, fermeture et création du texte |
| Mise en forme | Coins des boutons gras, italique, souligné et barré | Attributs du texte sélectionné modifiés |
| Collections | Marge du bouton plus et coin d’Annuler | Panneau ouvert puis fermé |
| État désactivé | Coin de Créer la collection sans nom et de Créer une copie sans annotation | Aucune action |
| Réglages | Coin d’Effacer l’historique | Confirmation affichée puis annulée |
| Menu Capturer | Espace entre icône et texte | Menu ouvert ; un clic sous le contrôle ne l’ouvre pas |
| Panneau vidéo | Marges des deux segments et coin d’Annuler | Choix modifié puis retour à la barre rapide |
| Barre rapide | Marges des onglets, coins du bouton compact et du logo | Filtres, taille des cartes et bibliothèque accessibles |
| Annotation | Coin du crayon, marges de Cadre et Texte, bord de la couleur bleue | Éditeur ouvert, cadre bleu et saisie de texte obtenus |
| Annulation d’annotation | Coins d’Annuler et Rétablir | Dessin supprimé puis rétabli |

Les autres outils d’annotation et les commandes conditionnelles utilisent les mêmes styles vérifiés. Leur fonctionnement complet n’a pas été rejoué dans cette passe ciblée sur les zones cliquables.

## Vérifications automatiques

`swift test -j 2` : 26 tests réussis, aucune erreur. La suite couvre notamment les annotations, l’historique, la recherche, le chiffrement, les captures Retina et l’import vidéo. Ces tests complètent les essais de clics ; ils ne les remplacent pas.

Compilation universelle arm64 et x86_64. Les essais d’interface ont été réalisés sur Apple Silicon ; aucune exécution sur un Mac Intel n’a été effectuée pour cette correction.

Compte rendu relu manuellement. Le correcteur rédactionnel facultatif n’a pas pu fonctionner, car sa dépendance spaCy est absente.
