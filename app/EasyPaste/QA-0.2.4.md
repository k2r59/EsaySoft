# EasyPaste 0.2.4 — bibliothèque et annotations

Version 0.2.4, build 9. Les deux interfaces validées en maquette ont été réalisées en SwiftUI et AppKit. Les illustrations des maquettes ne sont pas utilisées comme interface : les commandes, les aperçus et les données sont réels.

## Bibliothèque

- Recherche en tête de fenêtre, capture de zone directe, menu des autres captures, OCR et vidéo.
- Historique, favoris, pile, collections, corbeille et réglages dans la barre latérale.
- Cartes en grille ou en liste, sélection visible, favoris accessibles directement et barre d’actions sur la sélection.
- Filtres de contenu, d’application et de date conservés. La création de texte et les commandes de la barre rapide restent disponibles.
- Les cartes n’effectuent pas de requêtes réseau pour enrichir un lien. Les aperçus reflètent les données locales disponibles.

## Annotation

- Palette à gauche, canevas central, réglages contextuels et liste d’annotations à droite.
- Sélection et déplacement des objets, ajustement des extrémités, dessin au crayon, texte modifiable, cadres, surlignage, masquage opaque et recadrage.
- Couleur, épaisseur et trois extrémités de flèche. Un déplacement ou une modification continue d’épaisseur forme une seule étape d’annulation. L’historique d’annulation est limité à 100 états.
- Zoom de 10 à 400 %, ajustement et défilement. À 100 %, un pixel de l’image correspond à un pixel de l’écran.
- La saisie de texte se superpose au canevas sans déplacer l’image.
- Copie conservant l’original par défaut, remplacement explicite et case facultative de copie dans le presse-papiers. Le retour après enregistrement respecte la bibliothèque ou la barre rapide d’origine.

## Netteté et ressources

L’export reprend les pixels de l’image d’origine et produit un PNG sans perte. Le zoom ne change ni les coordonnées des annotations ni les dimensions de sortie. Seul un recadrage modifie ces dimensions.

La préparation des images et l’export restent hors du thread principal. L’aperçu de travail est limité à 4 096 pixels sur le grand côté ; les pixels natifs d’une image plus grande sont décodés à la demande pendant le zoom, puis libérés en revenant à Ajuster. La limite d’entrée de 50 mégapixels est conservée.

Le déplacement du pointeur invalide uniquement le canevas AppKit ; il ne publie pas chaque point aux panneaux SwiftUI. La bibliothèque conserve ses vues paresseuses, son chargement par lots de 80 éléments et son cache de miniatures borné.

## Vérifications

Le 18 octobre 2026, les 59 tests passent en Release (environ 5,3 s). Une exécution Debug précédente de 58 tests passe également. Le dernier test ajouté confirme que les mouvements du pointeur ne republient pas les panneaux SwiftUI et qu’un redimensionnement réduit à un point est rejeté sans effacer l’objet.

Le banc de recherche synthétique retrouve deux termes dans 10 000 notes en environ 32 ms en Release sur le Mac de développement. Cette mesure ne prétend pas décrire tous les historiques réels.

Les tests couvrent les zones de sélection des objets, les déplacements bornés, l’annulation/rétablissement, l’édition et la suppression du texte, les styles de flèche, le crayon, le zoom indépendant de l’export et la limite de l’historique d’annulation. Les tests existants de pixels, de copie, de stockage, de recherche et de vidéo sont conservés.

Deux tests de mise en page vérifient les largeurs minimales. Leurs rendus hors écran ont été inspectés à 1 000 × 620 pour l’annotation et 1 050 × 740 pour la bibliothèque.

Essais manuels dans une application de démonstration isolée :

- Clic dans la marge du filtre Images et du bouton Annoter.
- Recherche « reponse » retrouvant « Réponse », retour aux images et bascule grille/liste.
- Flèche, déplacement par la ligne, couleur, épaisseur, annulation par le bouton, rectangle, crayon et texte validé par Entrée.
- Zoom à 100 % avec défilement puis retour à Ajuster.
- Création d’une copie : une carte supplémentaire, à côté de l’originale.
- Remplacement : conservation du nombre de cartes et du titre, réouverture possible.
- Enregistrement avec la copie automatique décochée.

Les raccourcis utilisant Commande n’ont pas pu être confirmés avec les événements synthétiques du contrôle d’ordinateur ; un essai au clavier physique reste utile. Les boutons correspondants sont validés. Les essais vidéo et caméra réels de la version 0.2.3 restent documentés dans `QA-0.2.3.md` ; ils n’ont pas été répétés pour cette refonte d’interface. L’exécution Intel reste à vérifier sur un Mac Intel.

Le relevé ponctuel de l’app de démonstration au repos après fermeture de l’éditeur était de 0 % CPU et environ 183 Mio de mémoire résidente. Il ne constitue pas un profil de consommation prolongé.
