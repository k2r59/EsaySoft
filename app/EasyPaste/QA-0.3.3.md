# Validation EasyPaste 0.3.3

21 octobre 2026, Mac Apple Silicon, macOS 27.

## Correction

Les reconnaisseurs de clic simple et de double-clic étaient en concurrence.
Le clic simple pouvait attendre l’expiration du délai de double-clic système.
Un modificateur partagé les compose désormais simultanément : le premier clic
sélectionne, le double-clic conserve son action. Le second clic ne rebascule pas
une sélection multiple faite avec Cmd.

La sélection reste déclenchée au relâchement d’un clic valide. Aucun timer,
moniteur global de souris, accès au coffre ou calcul d’aperçu n’est ajouté.
Les surfaces cliquables, boutons enfants et fournisseurs de glisser-déposer
restent en place.

## Tests automatiques

- Suite Release : **204 tests, aucun échec**, 25,96 s.
- Quatre tests de sélection : modification synchrone sans collage ni rechargement,
  Cmd-clic et second clic, plage Maj-clic et navigation au clavier, 300 sélections
  successives sans action différée.
- Le seuil de 100 ms couvre les 300 changements du modèle en mémoire ; il ne
  constitue pas une mesure du délai entre un clic physique et l’affichage.
- Les tests existants de transfert d’images et de contenu structuré par
  `DragProvider` font partie de la suite.
- Compilation universelle arm64/x86_64 et vérification des deux architectures.

## Essais dans l’application

Exécutable de production 0.3.3, avec historique fictif isolé et collecte en pause.

- Clics à la souris dans les marges des cartes en grille et en liste.
- Ajout et retrait de sélection par Cmd-clic ; plage de trois cartes par Maj-clic.
- Bouton Favori et menu d’une carte sans déclencher le collage.
- Clic dans une carte de la barre rapide puis flèches droite/gauche : sélection
  de l’image, de la couleur et retour à l’image.
- Déplacement d’un texte fictif dans la corbeille puis restauration par double-clic.
- Les essais visuels confirment les actions ; ils ne mesurent pas la latence
  image par image. L’exécution sur Intel et macOS 15/26 n’est pas testée sur ce Mac.

L’interruption de session signalée pendant les essais concernait Codex.
EasyPaste était toujours en cours d’exécution et aucun rapport de crash EasyPaste
n’était présent dans les rapports de diagnostic utilisateur.

## Distribution

- Application et DMG signés Developer ID, notarisés et agrafés.
  Notarisation : `b37d950f-dc37-4dbf-8d84-63292030ad52`.
- Gatekeeper accepte les deux artefacts avec `Notarized Developer ID`.
- Les deux architectures ciblent macOS 15.0.
- Les 241 fichiers chiffrés du coffre utilisateur sont identiques après les essais
  sur les données fictives (comparaison SHA-256, sans déchiffrement).
- La préparation du DMG a utilisé le disque interne et le binaire universel
  déjà testé, pour éviter de recompiler sur le SSD externe pendant l’incident.
