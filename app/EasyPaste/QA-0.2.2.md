# EasyPaste 0.2.2 — netteté et réactivité

Validation du 18 octobre 2026 sur le Mac de développement. Les données des essais sont séparées de l’historique personnel. Aucun envoi iCloud.

## Changements

- Sélections alignées sur les pixels physiques avant la capture, y compris les coordonnées fractionnaires de la souris.
- Résolution native fournie par ScreenCaptureKit ; qualité maximale et format BGRA pour les zones et fenêtres.
- Assemblage d’écrans de densités différentes en arrière-plan : les pixels Retina restent intacts, les pixels 1× sont dupliqués sans lissage.
- Aperçu **Ajuster / 100 %**, dimensions en pixels visibles, décodage hors du fil principal et annulation des chargements devenus inutiles.
- Les petites images ne sont plus agrandies dans l’aperçu et l’éditeur. L’origine du dessin est alignée sur les pixels.
- Les recadrages seuls évitent une seconde image de travail pleine taille. Les annotations conservent le profil couleur RGB et les pixels hors des marques.

## Tests automatiques

38 tests passent en Debug et en Release, dont 12 nouveaux contrôles de qualité et de réactivité. Plusieurs exécutions intermédiaires ont aussi validé les 36 premiers tests avant les deux derniers ajouts.

| Contrôle | Résultat |
| --- | --- |
| PNG 752 × 271, 1 504 × 542 et 5 120 × 2 880, lignes d’un pixel | Tous les pixels identiques après encodage/décodage |
| Conservation chiffrée → copie → relecture du presse-papiers, trois répétitions | Octets PNG identiques à l’original |
| Glisser-déposer d’une image 5K | Octets PNG identiques à l’original |
| Aperçu ajusté, décodage natif et petites images | Dimensions et absence d’agrandissement validées |
| Sélections fractionnaires, coordonnées négatives, écrans 1× et 2× | Bords alignés, zone sélectionnée conservée |
| Assemblage 1× + 2× | Pixels Retina identiques et pixels 1× dupliqués exactement |
| Annotation, recadrage, export sans modification, profil Display P3 | Dimensions, couleurs et zones intactes vérifiées |
| Données invalides, dimensions non finies et limites mémoire | Rejet avant allocation de l’image complète |
| OCR, recherche, suppression, chiffrement, vidéo MP4, MCP | Tests existants toujours passants |

Sur le dernier essai Release : trois cycles 5K (PNG, aperçu, recadrage) prennent environ 0,67 s au total. Un témoin programmé toutes les 16 ms sur le fil de l’interface mesure un intervalle maximal de 20,2 ms. La recherche de deux termes dans 10 000 notes prend 35,5 ms. Ces mesures synthétiques ne sont pas un relevé des images par seconde de l’interface.

## Essais dans l’application signée

- Captures réelles de zone : 790 × 360 pixels sur l’écran 1× et 1 580 × 720 sur l’écran 2× pour la même taille logique.
- Capture d’une fenêtre : PNG de 2 560 × 1 319 pixels, enregistré et copié.
- Annulation de sélection sans ajout à l’historique de démonstration.
- Ouverture d’aperçu, passages successifs Ajuster / 100 %, défilement et copie : les octets recopiés sont identiques à ceux de la capture.
- Ouverture et fermeture de l’éditeur d’annotation. Le dessin et l’export de ses outils sont vérifiés par les tests automatiques ; le glissement manuel dans cet éditeur n’a pas pu être validé avec l’outil de contrôle pendant cette session.
- Après les essais, un relevé du processus indique 0,0 % CPU et environ 109 Mio de mémoire résidente, contre environ 167 Mio pendant l’aperçu. Il s’agit de relevés ponctuels, pas d’un plafond garanti.

## Limites

Un écran 1× contient moins de détails qu’un écran Retina pour un texte de même taille logique. Agrandir un PNG après sa capture ou l’afficher réduit dans une messagerie peut modifier sa netteté apparente. EasyPaste conserve la résolution disponible ; ces tests ne promettent ni la reconstruction de détails absents ni l’absence de tout incident sur tous les Macs.

Les vidéos gardent leur encodage H.264 et leurs réglages existants. Le parcours vidéo complet avec microphone n’a pas été rejoué pour cette correction de captures fixes. Le test d’import, lecture, copie et suppression d’un vrai MP4 reste passant.
