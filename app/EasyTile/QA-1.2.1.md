# Validation EasyTile 1.2.1 — 22 octobre 2026

## Cause et correction

Le chemin de glissement lisait synchroniquement la position et la taille de la fenêtre distante à chaque événement de souris et toutes les 40 ms. Il repositionnait et remontait aussi l’aperçu à chaque passage, y compris à destination inchangée.

La lecture distante est désormais limitée à la confirmation initiale d’un déplacement réel. Ensuite le suivi utilise la souris et la géométrie locale. Les événements mettent la destination à jour immédiatement ; le timer reste un secours, sans ajouter de délai aux événements. Une position identique est ignorée, et un déplacement à l’intérieur du même cadre ne provoque plus de redessin. Le menu réutilise son NSHostingView. Les changements d’écran invalident le geste ; la fin par événement ou par timer ne peut placer deux fois la fenêtre.

L’énumération des fenêtres à l’activation d’une application est suspendue pendant le geste. Les contrôles de confiance TCC ne sont plus répétés pour chaque mouvement ; la surveillance existante et la vérification avant placement restent actives.

## Tests

35 tests Release réussis, aucune erreur, dont 9 nouveaux tests de suivi :

- Petit mouvement sans lecture distante.
- Glissement de contenu sans ouverture de menu.
- Redimensionnement avec changement d’origine : annulation.
- Fenêtre devenue indisponible avant confirmation.
- Déplacement de fenêtre détecté avec retard alors que le pointeur s’est arrêté.
- 10 000 mouvements après confirmation sans aucun nouvel appel de lecture distante.
- Cadre inchangé, changement de cadre, espaces entre cadres, sortie et retour.
- Réinitialisation de la destination à un autre écran ou geste.
- 10 000 changements alternés, dernière destination toujours correcte : environ 3,9 ms pour le calcul seul sur le Mac de développement. Ce chiffre ne mesure pas le délai visuel complet.

Les 26 tests existants de géométrie, apparence, rendu des pages et palettes, lancement et mises à jour passent aussi. Une seconde exécution complète a été effectuée après ajustement de la fin de glissement.

## Essais dans la version installée

- EasyTile 1.2.1 démarre avec Accessibilité déjà autorisée, sans nouvel accès demandé.
- Une application jetable TileFixture a servi de cible : placement par le bouton Gauche, puis Annuler. Le redimensionnement est visible et l’annulation restitue la taille initiale. L’app signale un ajustement de taille pour le premier placement.
- La fenêtre de test est fermée après contrôle. Aucune fenêtre de travail n’a servi de cible.
- Empreintes des cinq préférences applicatives préexistantes identiques, y compris dispositions, espacement et activation du menu de glissement.
- Le passage continu entre plusieurs cadres avec le bouton physique maintenu ne peut pas être évalué fidèlement par les entrées synthétiques de l’outil ; un retour utilisateur a été demandé après installation. Aucun chiffre de latence visuelle ni résultat de cet essai n’est présumé.

## Distribution

Compilation universelle Intel / Apple Silicon, macOS 15 minimum. Signature Developer ID Les papas du code, identifiant inchangé app.easytile.mac. Notarisation acceptée : `43c4ecc7-1192-46f4-bbff-e2695ee7edbb`. Tickets attachés au DMG et à l’application, contrôles Gatekeeper réussis. Exécution interactive sur Apple Silicon ; aucun essai matériel Intel dans cette session.

Le guide UI/UX consulté n’a pas de correspondance vérifiée pour ce problème de suivi AppKit. Les choix reposent sur le chemin de code et les tests de non-régression, en conservant les autres modes de placement accessibles au clavier et par boutons.
