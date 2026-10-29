# Contrôle qualité EasyMusic 0.5.0

**Contrôle QA : 10/10 sur la matrice ci-dessous.** Trois suites complètes de 133 tests passent, les scénarios visibles ont été vérifiés dans une bibliothèque QA isolée, et le paquet 0.5.0 / build 7 est signé, notarisé et validé avec son flux de mise à jour. Aucun défaut bloquant ne reste ouvert dans ce périmètre. La diffusion peut être effectuée par l’agent principal ; cet agent QA n’a rien publié.

La version 0.4.1 n’a pas été publiée. Son audit, conservé dans `QA-0.4.1.md`, décrit les contrôles initiaux et leurs corrections ; il ne remplace pas les tests de la version 0.5.0.

## Matrice de validation

| # | Catégorie | Preuve attendue en 0.5.0 | État |
|---|---|---|---|
| 1 | Recherche et navigation | Accueil iTunes, filtres titre/album/artiste, livres audio→chapitres→Retour, fiche ouverture/fermeture. | PASS : QA2/QA3, recherche et navigation réelles |
| 2 | Lecture et extrait | Streaming complet sans téléchargement implicite, local prioritaire, extrait ≤ 30 s, annulation et dernier clic gagnant. | PASS : tests ciblés, corrections et QA2 |
| 3 | Téléchargements | Action explicite indépendante du streaming, audio seul, fallback strict, deux tâches, dédoublonnage. | PASS : suites globales finales et preuves décrites ci-dessous |
| 4 | Bibliothèque | Aucune entrée/fichier musical créé par Lire distant ; fichier local disparu, bitrate et persistance cohérents. | PASS : suites globales finales et preuves décrites ci-dessous |
| 5 | Playlists | CRUD, appartenance multiple, couvertures, fichiers conservés. | PASS : suites globales finales et preuves décrites ci-dessous |
| 6 | Imports/sync | Sources publiques, avertissement Spotify, lien conservé, badge, renommage et ajouts préservés. | PASS : suites globales finales et preuves décrites ci-dessous |
| 7 | Conversion/export | Audio lisible, M3U ordonné, aucun écrasement, erreur partielle. | PASS : suites globales finales et preuves décrites ci-dessous |
| 8 | Lecteur | File mixte local/distant, play/pause/seek, shuffle/repeat, événements obsolètes ignorés, erreurs streaming bornées. | PASS : tests ciblés, corrections et QA2 |
| 9 | Réglages/retours UI | Messages de streaming sans référence à un fichier inexistant, chargement cohérent, sortie/volume et formulaires. | PASS : commandes testées, chargement/erreurs et transitions validés |
| 10 | Distribution | Version 0.5.0 / build 7, universalité, signature, notarisation, tickets, flux Sparkle signé, installation différée si occupé. | PASS : paquet universel, signature Developer ID, Apple Accepted, tickets et signatures Sparkle vérifiés |

## Tests préparés

`RequestedPlaybackTests.swift` a été réécrit pour le nouveau contrat : résolveur injecté et WAV synthétiques de 60 secondes. Il couvre lecture distante sans transfert ni bibliothèque, annulation avec réponse tardive, dernière intention, erreur de résolution, priorité locale, téléchargement explicite conservant l’AVPlayerItem, file mixte/shuffle/fin, extrait annulant une préparation, lecture au-delà 30 s et extrait arrêté, fin d’un ancien item ignorée, fallback limité à trois sources avec exclusions, erreur d’un ancien item ignorée, et correspondance du titre Renaud.

`QAActionTests.swift` conserve les neuf régressions initiales, ajoute un dixième contrôle d’ajout distant sans téléchargement, avec adaptation de l’assertion d’ordre à la file unifiée de Track.

Plan complet : `QA-STREAMING-0.5.0.md`. Aucun 10/10 attribué avant exécution des nouvelles preuves.


## Contrôle déterministe du nouveau lecteur

Commande : `swift test --filter 'RequestedPlaybackTests|QAActionTests'`, avec bibliothèques temporaires et WAV synthétiques de 60 s ; aucun service réseau utilisé par ces scénarios.

| Passe | Fin (29 octobre 2026, Europe/Paris) | Durée | Résultat | Journal |
|---|---|---|---|---|
| 1 | 12:15:15.390 | 1,155 s | 23 tests, 0 échec, 0 ignoré | `.tools/qa-streaming-store-pass1.log` |
| 2 | 12:15:49.028 | 1,807 s | 23 tests, 0 échec, 0 ignoré | `.tools/qa-streaming-store-pass2.log` |

La passe 2 renforce le test de durée : le lecteur se déplace à 31 s puis sa position avance réellement au-delà de 31,2 s avec `AVPlayer.timeControlStatus == .playing`. La pré-écoute du même fichier s’arrête à 30 s. Les assertions vérifient aussi les 13 scénarios du lecteur et les 10 régressions QA ; les deux suites sont vertes.

Le test d’erreur en lecture déclenche trois échecs successifs sur trois URL source distinctes, constate les exclusions transmises au résolveur puis l’arrêt avec message sans quatrième tentative. Un événement de fin ou une erreur portant sur un ancien AVPlayerItem ne change pas le morceau courant. Le téléchargement explicite pendant le streaming ajoute le fichier local tout en conservant exactement l’AVPlayerItem en cours.

Ces résultats ne remplacent pas les essais réseau du résolveur, la suite globale, ni la passe visuelle du nouveau binaire. Aucun 10/10 final attribué à ce stade.

## Première passe visuelle streaming et défauts détectés

Binaire QA isolé `EasyMusicQA-Streaming.app`, données `Data050` : 3 WAV locaux et un titre Renaud distant. Lire sur la playlist démarre le flux de 3:28 ; pause/reprise et déplacement à 0:40 fonctionnent, puis la position avance à 0:45. Suivant passe à un WAV local de 1:00 et Précédent revient au flux. Ajouter le titre distant à une seconde liste met son compteur à 1 sans transfert. Contrôle indépendant JSON/disque : toujours 3 LocalTrack et uniquement les 3 WAV, le titre distant est dans addedTracks. L’icône Télécharger reste affichée.

La revue a ensuite trouvé deux défauts nécessitant correction et nouvelle passe :

- Après un flux au-delà 30 s, la pré-écoute locale pouvait rester à 0:00, bouton Lire, sans erreur ; elle fonctionnait au second clic. L’observateur périodique pouvait appliquer un tick de l’ancien item au nouvel extrait. Le code a été corrigé pour rattacher l’observateur à l’item et lire son temps courant ; test renforcé avec progression de l’extrait depuis le début après un flux à 39 s.
- La recherche «La ballade nord-irlandaise Renaud» mettait une reprise de Perrot Olivier avant l’original. La recherche Artistes «Renaud» plaçait aussi un homonyme en premier à cause du tri lexical des identifiants. Le classement a ensuite été corrigé et vérifié dans la passe QA3 ci-dessous.

L’agent principal a également identifié Suivant en fin de file pendant une connexion : il fallait annuler la résolution pour éviter une lecture tardive. Un quatorzième test RequestedPlayback a été ajouté pour ce cas.

## Passe visuelle après correction des transitions

Binaire `EasyMusicQA-Streaming2.app`, première instance quittée par le menu et absence de son PID vérifiée avant ouverture (données QA partagées uniquement).

- Playlist distante seule : Lire puis Suivant pendant la connexion annule la lecture. Aucun titre actif, bouton désactivé, aucune lecture tardive à la seconde observation.
- Renaud à 0:54 puis pré-écoute locale : l’extrait repart à 0:00, progresse à 0:17 puis s’arrête à 0:30. Le défaut de tick obsolète n’est plus reproduit.
- Téléchargement explicite pendant le flux : lancé à 0:20, progression lecture à 0:29 puis 1:02 après fin de transfert, durée toujours3:28. La position continue et le lecteur ne redémarre pas après le transfert. La coche locale et le débit ≈ 134 kb/s apparaissent.
- JSON/disque après action explicite : passage de 3 à 4 LocalTrack et apparition d’un seul fichier audio supplémentaire (3 640 264 octets). `ffprobe` confirme une piste Opus audio et zéro piste vidéo, durée 217,441 s. Les trois WAV restent présents. Avant cette action explicite, plusieurs lectures et l’ajout à la seconde playlist n’avaient rien téléchargé.
- Accueil : attribution «Top ventes France · iTunes» visible.
- Livres audio → «Trop la classe ! (Histoires)» : pistes affichées en «Chapitre» ; Retour restaure la catégorie et ses livres.

Tests de transition relus dans `.tools/qa-0.5.0-transitions.log` : **24 tests, 0 échec**, fin 12:29:28.893, durée 2,563 s. Cela inclut les 14 tests RequestedPlayback et10 tests QAAction ; progression depuis 39 s puis nouvel extrait qui avance depuis le début vérifiée avant arrêt à 30 s.

À la fin de cette passe, le classement titre + artiste, les homonymes, les relations artiste/album des fiches et la navigation restaient à vérifier. La passe QA3 ci-dessous clôt ces contrôles.


## Dernière passe visuelle — QA3

Binaire `EasyMusicQA-Streaming3.app` (identifiant `local.easymusic.qa050c`) compilé avec les sources finales. Il réutilise exclusivement la fixture `Data050`. Les commandes du lecteur inchangées depuis QA2 gardent leurs preuves ci-dessus.

- Recherche «La ballade nord-irlandaise Renaud» : premier résultat «La ballade nord-irlandaise — Renaud», versions originales avant reprises/live. Le défaut du meilleur résultat Perrot Olivier n’est plus présent.
- Clic sur la version Deezer 624593372 : fiche Renaud, album associé «Marchand de cailloux» ; ouverture de cet album montre notamment le titre ciblé dans sa liste. Retour restaure les résultats de recherche.
- Filtre Artistes, requête «Renaud» : premier Renaud ouvre un catalogue contenant Mistral gagnant, Manhattan-Kaboul, Morgane de toi, Hexagone ; l’homonyme précédemment ouvert n’est plus premier.
- Filtre Albums, requête «Mistral gagnant» : album de Renaud en tête ; ouverture avec Miss Maggie, La pêche à la ligne, Mistral gagnant et les autres morceaux attendus. La fiche de Mistral gagnant (Deezer 5151905) affiche Renaud et l’album Mistral gagnant.
- Fermeture de fiche et Retour vers les albums : contexte et requête conservés.
- Filtre Styles avec Jazz : entrée Jazz étiquetée Style. Filtre Playlists : entrées étiquetées Playlist. Effacement du champ : texte vide, action de recherche désactivée.

La session QA3 a été quittée par son menu ; absence de processus EasyMusicQA050 confirmée avant de préparer la distribution. Aucun compte, vraie bibliothèque ou playlist utilisateur n’a été modifié.

Les neuf catégories fonctionnelles sont vérifiées. Les trois suites complètes et les contrôles de distribution ci-dessous clôturent la matrice.


## Trois suites finales complètes

Commande : `EASYMUSIC_NETWORK_TESTS=1 EASYMUSIC_RENAUD_TEST=1 swift test`. Les journaux ont été relus par l’agent QA : résumé final, absence de test échoué et de test ignoré. Horaires du 29 octobre 2026, Europe/Paris.

| Passe | Début | Fin | Durée | Résultat | Journal |
|---|---|---|---|---|---|
| 1 | 12:37:42.726 | 12:39:40.884 | 118,158 s | 133 tests, 0 échec, 0 ignoré | `.tools/qa-0.5.0-final-pass1.log` |
| 2 | 12:39:43.375 | 12:41:47.462 | 124,087 s | 133 tests, 0 échec, 0 ignoré | `.tools/qa-0.5.0-final-pass2.log` |
| 3 | 12:41:48.778 | 12:43:49.632 | 120,854 s | 133 tests, 0 échec, 0 ignoré | `.tools/qa-0.5.0-final-pass3.log` |

**399 exécutions de tests réussies.** Chaque passe couvre les 14 scénarios RequestedPlayback, les 10 régressions QAAction, le résolveur streaming et ses annulations, la lecture distante au-delà de 30 secondes, les sources publiques, le téléchargement réel Renaud, les imports, la synchronisation, le classement des recherches et les relations catalogue. Les sources produit sont restées gelées entre ces trois exécutions.

Les commandes de création, renommage, suppression, couverture, export, paramètres et sortie audio ont été contrôlées sur la fixture précédente, décrite dans `QA-0.4.1.md`. Leur comportement reste couvert par les suites finales ; les changements de lecture distante, de file mixte et d’ajout aux listes ont été rejoués dans les nouvelles passes GUI et automatisées de la version 0.5.0.

## Limites du contrôle

- Le score représente cette matrice, ces scénarios et les échantillons datés. Les catalogues et flux externes peuvent devenir indisponibles ou changer après publication.
- Les vérifications audio portent sur les pistes audio présentes, la compatibilité AVFoundation, la durée et la progression réelle du lecteur. Elles ne constituent pas une mesure de qualité acoustique.
- L’export destiné à Offline Music a été vérifié sur Mac. Aucun iPhone n’était connecté et aucune synchronisation automatique avec cette application n’est promise.
- Le paquet contient les architectures arm64 et x86_64 ; l’exécution a été contrôlée sur Apple Silicon, sans Mac Intel physique.
- L’installation Sparkle depuis la version publique 0.4.0 ne peut être observée avant publication. La signature du paquet et du flux, ainsi que les protections pendant les opérations, sont contrôlées avant diffusion. Le flux public et le fichier diffusé doivent être vérifiés après publication par l’agent principal.


## Distribution finale vérifiée

Contrôle indépendant de l’agent QA le 29 octobre 2026, après la préparation du paquet final par l’agent principal :

- Application : `dist/EasyMusic-0.5.0.app`. Info.plist confirme version **0.5.0**, build **7**, identifiant `local.easymusic.app`, minimum macOS 13.0 et flux HTTPS `https://k2r59.github.io/EsaySoft/easymusic/appcast.xml`.
- Exécutable universel confirmé par `file` : **arm64 et x86_64**.
- `codesign --verify --deep --strict --verbose=2` réussit, y compris les composants Sparkle. Signature **Developer ID Application: Les papas du code (WN9MHL56A9)**, runtime renforcé.
- Notarisation Apple **Accepted**, identifiant `cd5247f1-b43a-495f-84b6-e5dfa3ff0edd`, relu dans `.tools/0.5.0-notary.log`.
- `spctl --assess --type execute --verbose=2` retourne **accepted / Notarized Developer ID**.
- `xcrun stapler validate` réussit sur l’application et le DMG final.
- `dist/appcast.xml` annonce bien **7 / 0.5.0**, avec la bonne URL de version et la longueur exacte du DMG. Les deux signatures Ed25519, celle du flux et celle du DMG, ont été vérifiées à nouveau avec `scripts/verify-update.swift`, en utilisant la clé publique contenue dans l’application : **Signature valide** dans les deux cas. Aucun accès à une clé privée n’a été nécessaire pour cette vérification.

DMG final : `dist/EasyMusic-0.5.0-universal.dmg`, **134 531 204 octets**. SHA-256 :

```text
4f92e172003d7bbd8a4bbc0e38e90877b6acccbb4e1cab5dca9451ecf2cd92fc
```

**Décision QA : 10 catégories vérifiées sur 10.** Les défauts découverts ont été corrigés puis retestés ; les trois passes finales exécutent chacune 133 tests sans échec ni cas ignoré. La publication est autorisée dans le périmètre et avec les limites explicités dans ce rapport. Le contrôle du flux public et du téléchargement distribué reste une vérification après publication, à réaliser par l’agent principal.
