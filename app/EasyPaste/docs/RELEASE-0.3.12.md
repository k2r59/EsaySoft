# EasyPaste 0.3.12

- Le curseur de capture affiche une croix et des coordonnées, et reste visible au passage entre les écrans.
- Une nouvelle copie ramène l’historique au début, même après une recherche. Une réouverture sans nouvelle copie conserve la sélection.
- Les copies provenant d’un autre appareil Apple sont attendues lorsqu’elles arrivent avec du retard, sans bloquer l’interface.
- Les photos reçues sous forme de fichiers peuvent être intégrées comme images, en pleine résolution, avec miniature et aperçu.
- Si macOS protège le dossier de transfert, une autorisation ciblée est proposée dans Réglages → Confidentialité. Les fichiers d’origine restent conservés ; la récupération crée des copies image dans l’historique.

Validation : 355 tests automatiques réussis, contrôle du retour au début de l’historique et essai réel d’une image copiée depuis la galerie iPhone, avec miniature et aperçu agrandi.
