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

## Essais sur le Mac — 21 octobre 2026

- Clair, Sombre et Automatique changent l’apparence immédiatement. Automatique suit le thème sombre du Mac. Palette et éditeur vérifiés en clair ; toutes les vues sont rendues dans les deux thèmes par les tests.
- Ouverture au démarrage : inscription réelle réussie (`enabled`), puis désinscription réussie. L’option a été laissée désactivée. Aucune déconnexion de session n’a été imposée pour tester un vrai démarrage.
- Les options Sparkle réagissent correctement : désactiver les vérifications désactive aussi l’installation automatique. Les vérifications quotidiennes restent activées, l’installation automatique reste facultative.
- Le menu de mise à jour est désactivé tant que l’éditeur est ouvert ; il redevient disponible après annulation.
- Cycle OTA natif réussi depuis un exemplaire signé avec le même identifiant et un numéro de build inférieur : recherche du flux public, annonce 1.2.0, téléchargement, extraction, Installer et relancer. Le nouveau processus a été constaté avant toute réouverture par l’outil de contrôle.
- Après relance : version 1.2.0, Accessibilité toujours autorisée, contrôle « à jour » réussi. Exécutable et Info.plist identiques à ceux du paquet publié. Empreintes des dispositions, espacement et préférence de glissement inchangées.
- Signature Developer ID inchangée (`app.easytile.mac`, équipe `WN9MHL56A9`). Notarisation Apple acceptée : `ca820ce5-60c2-499c-8e07-e470e90eda62`. Gatekeeper accepte le DMG et l’app installée.
- Deux architectures vérifiées, déploiement minimal macOS 15.0. Les essais interactifs ont lieu sur Apple Silicon ; l’exécution sur Intel et un vrai changement de session restent non testés.
- Flux HTTPS publié identique au fichier local, signature Ed25519 valide. Flux EasyPaste 0.3.2 et EasyShoot 0.3.0 préservés.

Le test OTA valide l’installation immédiate et la relance. Une installation différée à une fermeture future dépend du cycle automatique de Sparkle ; elle n’a pas fait l’objet d’un second cycle public pendant cette validation.
