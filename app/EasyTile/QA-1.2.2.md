# Validation EasyTile 1.2.2 — 22 octobre 2026

## Retour utilisateur et correction

Après la 1.2.1, les transitions simples sont plus réactives, mais un balayage sur tous les modèles reste perçu comme lent. Les tests de géométrie de la 1.2.1 ne mesuraient pas cette charge de rendu.

Le menu de glissement utilise désormais des calques AppKit persistants. Un changement de zone ne modifie que l’ancienne et la nouvelle surbrillance, ainsi que les libellés concernés. Le grand aperçu dessine son rectangle dans une fenêtre transparente de taille fixe pour l’écran courant, sans redimensionnement de NSWindow à chaque zone. Les espaces entre zones masquent le rectangle sans remettre la fenêtre dans la pile d’affichage.

Les événements sont regroupés sur un intervalle de 1/60 s, en échantillonnant la position actuelle, sans file de positions anciennes. Le relâchement force une dernière lecture. La confirmation initiale du déplacement, l’annulation et la suspension des lectures AX répétées restent celles de la 1.2.1.

## Tests automatiques et rendu

40 tests Release réussis, aucune erreur, deux exécutions complètes après ajout des tests de rendu (une avec snapshots, une après ajout des contrôles de transparence).

- 2 000 transitions sur les 20 zones des huit modèles : une seule zone active, mêmes objets calques et même nombre de sous-vues, aucune animation implicite en attente.
- Nouvelle configuration du menu : aucune zone cachée ni ancienne surbrillance conservée.
- 1 800 destinations dans l’aperçu : même fenêtre, frame stable sur chaque écran, coordonnées correctes pour écran principal, à gauche et au-dessus ; masquage entre modèles.
- 1 000 événements/s simulés : travail borné à 60 échantillons/s, relâchement accepté entre deux frames, geste suivant immédiat.
- Snapshots natifs clair/sombre inspectés : sélection, libellés, position de l’aperçu et transparence conservés. Alpha du remplissage 0,13 et bordure 0,85.
- Les tests existants de placement géométrique, détection du mouvement/redimensionnement, préférences, lancement, mises à jour et mise en page passent.

Le coût p95 des mutations AppKit/calques sur les 2 000 transitions est d’environ 0,030 ms. Cela exclut le délai de présentation à l’écran.

## Comparaison avec affichage réel

Deux applications de test locales et jetables ont affiché les mêmes 20 zones à 60 sollicitations/s pendant 12 secondes, sur une surface d’écran de 5 120 × 1 320 points. L’une reprend le menu SwiftUI et le redimensionnement d’aperçu de la 1.2.1 ; l’autre utilise les nouvelles classes de rendu. Aucun déplacement de fenêtre de travail, aucune modification de préférences, aucune autorisation supplémentaire.

| Mesure du processus de test | Rendu 1.2.1 | Rendu 1.2.2 |
| --- | ---: | ---: |
| Transitions effectuées | 716 | 715 |
| Temps CPU sur 12 s | 3,495 s | 0,934 s |
| CPU moyen, un cœur = 100 % | 29,1 % | 7,8 % |
| Pic RSS | 90,2 Mio | 97,7 Mio |
| Intervalle timer p95 | 17,5 ms | 17,7 ms |
| Intervalle timer maximal, démarrage inclus | 79,4 ms | 96,7 ms |

Le temps CPU du processus est réduit d’environ 73 %, avec environ 7,5 Mio de mémoire de plus pour conserver la surface fixe. La cadence des timers est comparable. Ces mesures ne couvrent ni le coût GPU/WindowServer, ni la latence souris-vers-pixel, et ne prouvent pas l’absence de saccades dans toutes les apps. Le geste physique continu avec la fenêtre maintenue reste à confirmer par l’utilisateur ; l’outil d’entrées synthétiques ne le reproduit pas fidèlement.

Les exécutables de test sont fermés après les mesures. Compilation et packaging sur le disque interne, parallélisme limité à deux tâches.

## Distribution

Version 1.2.2, build 5, macOS 15 minimum, Intel et Apple Silicon. Identifiant app.easytile.mac et équipe Developer ID Les papas du code inchangés. Notarisation acceptée : `c66a3004-f1bb-482f-a31e-b69fc12fb8e2`. Tickets attachés au DMG et à l’app, contrôles Gatekeeper réussis. Version normale installée dans /Applications et ouverte : 1.2.2 affiché, Accessibilité conservée, aucune nouvelle demande. Les empreintes des cinq préférences applicatives sont inchangées, y compris dispositions, espacement et menu de glissement. Le binaire installé est identique à celui du paquet signé. Exécution testée sur Apple Silicon ; aucun essai matériel Intel.
