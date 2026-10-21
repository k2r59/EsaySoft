# Vérifications EasyPaste 0.3.5 — 21 octobre 2026

## Résultat

- 215 tests Release réussis, aucune défaillance (27,7 secondes).
- Compilation universelle Intel / Apple Silicon réussie.
- Signature Developer ID Les papas du code, notarisation Apple acceptée : `c2461f56-8630-479f-b0e1-1afe730b9dcd`.
- Tickets attachés à l’application et au DMG ; Gatekeeper accepte les deux.

## Essais dans l’application

Session de démonstration signée, installée temporairement au chemin habituel, avec un historique fictif isolé et la collecte arrêtée. Autorisation Accessibilité activée avec l’accord et la validation système de l’utilisateur.

- Au lancement, la barre du bas apparaît seule.
- Le bouton de bibliothèque ouvre la grande fenêtre. Le bouton Barre rapide revient à la barre et masque la bibliothèque.
- Réouverture de la barre après collage : sélection précédente conservée.
- Navigation gauche/droite puis Entrée : le texte fictif « Raccourcis utiles… » est inséré dans le document TextEdit de test, sans ⌘V supplémentaire.
- Un clic dans l’espace vide de la carte « Réponse à garder » insère son texte dans le même document TextEdit. Le contenu ajouté est confirmé dans le document.
- L’éditeur de texte reste accessible lors d’une tentative de réouverture de l’app ; Annuler revient à la bibliothèque.
- Les 264 fichiers préexistants de l’historique ont conservé exactement leur empreinte SHA-256 pendant les essais.

L’outil de contrôle synthétise les raccourcis vers une application et ne déclenche pas fiablement le raccourci global Carbon ⇧⌘V. Le chemin partagé de présentation de la barre a été vérifié par les boutons et la réouverture ; aucune validation physique de ce raccourci global n’est revendiquée ici. Le lancement automatique de session est conservé par le code et n’a pas été retesté par une fermeture de session.

## Portée

Ce correctif change la présentation des fenêtres. Il conserve les correctifs 0.3.4 de sélection à la nouvelle copie, collage en un clic et pointe des flèches. Les tests correspondants restent dans la suite Release. Les essais de cette version valident aussi le collage inter-applications, qui était bloqué par l’autorisation Accessibilité lors de la publication 0.3.4.
