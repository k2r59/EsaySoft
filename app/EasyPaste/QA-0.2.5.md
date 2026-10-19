# EasyPaste 0.2.5 : textes et aide

Version 0.2.5, build 10. La disposition de la bibliothèque et de l’annotation reste celle de la version 0.2.4.

Les titres et actions utilisent des libellés directs. Les slogans et les explications répétées ont été retirés de l’accueil, des réglages, de l’éditeur de texte et de la préparation vidéo.

Dans les réglages, les limites de stockage, les raccourcis clavier et les détails de confidentialité se déplient à la demande. Toute la largeur de chaque ligne est cliquable. Le bouton « ? » de l’annotation donne l’aide de l’outil sélectionné.

Les conséquences d’un remplacement, d’un masquage ou d’une suppression restent indiquées au moment de l’action. Les détails de protection des données restent consultables. Les réglages et la fenêtre À propos lisent désormais la version dans le fichier Info.plist de l’application.

## Vérifications du 19 octobre 2026

Les 59 tests existants passent en Release sur Apple Silicon, en environ 5,3 secondes. Aucun moteur de capture, de vidéo, d’export ou de stockage n’a été modifié. Seuls certains messages de résultat ont été raccourcis dans ces composants.

Des rendus natifs hors écran ont été inspectés pour la bibliothèque à 1 050 × 740, l’annotation à 1 000 × 620 en modes copie et remplacement, les réglages et la préparation vidéo. Les rendus utilisent un historique temporaire isolé. Le banc de recherche retrouve deux termes dans 10 000 notes en environ 31 ms sur le Mac de développement.

Le contrôle interactif des applications macOS n’était pas disponible pendant cette passe. Les clics réels sur les nouvelles aides et les essais caméra, microphone et vidéo n’ont donc pas été répétés. Les contrôles utilisent les boutons natifs et le style existant qui rend toute leur surface cliquable. Les essais précédents restent décrits dans [QA-0.2.3.md](QA-0.2.3.md) et [QA-0.2.4.md](QA-0.2.4.md).

La compilation contient les architectures Apple Silicon et Intel. L’exécution sur un Mac Intel reste à vérifier.
