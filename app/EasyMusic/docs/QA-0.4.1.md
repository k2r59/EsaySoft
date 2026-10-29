# Contrôle qualité EasyMusic 0.4.1

Publication suspendue jusqu’à validation des dix catégories ci-dessous. Un point correspond à une catégorie entièrement contrôlée, pas à une impression de qualité. Une action non vérifiée reste « à vérifier » et ne vaut pas un point.

## Inventaire des actions et critères

| # | Catégorie | Actions et résultat attendu | État |
|---|---|---|---|
| 1 | Recherche et navigation | Recherche texte/lien, filtres Tout/Styles/Titres/Albums/Artistes/Playlists, effacer, ouvrir collection, cliquer titre, détails/fermeture : contenu et navigation correspondant à l’intention. | EN ATTENTE : tests passent ; dernier contrôle UI du binaire final bloqué par CUA |
| 2 | Lecture et extrait | Pochette lance le morceau local ou prépare un morceau distant, pause/reprise, extrait distinct ≤30s, changement de morceau pendant préparation sans lecture obsolète. | PASS : 5 tests d’intention, 3 téléchargements Renaud, lecture/extrait GUI |
| 3 | Téléchargements | Audio uniquement, formats compatibles accessibles, 2 tâches maximum, reprise après échec, autre source suffisamment proche, dédoublonnage même enregistrement, erreurs visibles. | PASS : défaut reproduit puis corrigé, suite finale et audio réel |
| 4 | Bibliothèque locale | Fichiers conservés, état déjà téléchargé exact, débit mesuré non inventé, persistance, fichier absent redonne possibilité de télécharger. | PASS : suite finale et commandes GUI |
| 5 | Playlists locales | Créer, renommer, supprimer après confirmation, ajouter/enlever dans plusieurs listes, pochette personnalisée/premier titre, conserver fichiers audio. | PASS : régression corrigée, CRUD/multi-appartenance/couverture GUI |
| 6 | Import et synchronisation | Liens Spotify/Deezer/YouTube, pagination, avertissement de partialité, lien original conservé, badge, sync manuelle, renommage/couverture/ajouts locaux conservés, pas de recréation après suppression. | PASS : imports publics réels, tests sync/badge et conservation |
| 7 | Conversion et export | Conversion audio lisible, export ordonné avec M3U, chemins sûrs, pas d’écrasement/suppression d’existant, erreur partielle explicite. | PASS : régression corrigée, conversion réelle et export GUI vérifié |
| 8 | Commandes du lecteur | Précédent/suivant, fin de file/répétition, aléatoire et retour ordre initial, barre de progression, volume/muet, file, plein écran/sortie audio. | PASS : régression corrigée, commandes GUI et arrêt extrait à 30 s |
| 9 | Réglages et retours UI | Choix dossier/format, reset suggestions, formulaires et annulation, aides des icônes, erreurs visibles, état de chargement, textes cohérents. | PASS : suite finale et commandes GUI |
| 10 | Distribution et mises à jour | Build universel, signature, version/feed, absence publication avant validation, blocage mise à jour pendant actions, flux signé. | PASS : signature, universalité, notarisation, ticket et feed staging vérifiés |

## Passe 1 — reproduction des défauts

Tests `QAActionTests.swift`, exécutés sur des bibliothèques temporaires et des fichiers synthétiques. Aucune suppression de données utilisateur.

- `testManualRemoteAdditionSurvivesSourceSynchronization` : ÉCHEC. `setMembership` stocke le morceau distant dans la portion importée, ensuite remplacée en synchronisation.
- `testRemoveLocalTrackAlsoRemovesImportedMembership` : ÉCHEC. L’ancien retrait ne modifie que `trackIDs`.
- `testDisablingShuffleRestoresPlaylistOrder` : ÉCHEC. Désactivation aléatoire trie par ordre global de la bibliothèque.
- `testConversionNeverDeletesPreexistingOutput` : ÉCHEC. Échec ffmpeg provoque l’effacement de la sortie préexistante.
- `testSameRecordingAcrossSourcesIsNotDownloadedTwiceConcurrently` : ÉCHEC. Deux identités de source lancent deux transferts pour le même enregistrement.

Preuve : `.tools/qa-actions-first-expanded.log` — 5 tests exécutés, 5 échecs reproduits. Les tests ont été transmis à l’agent principal pour correction. Aucun 10/10 attribué.

## Passes 2 et 3

À remplir après les corrections et le contrôle du binaire final. La passe 2 vérifie la suite automatisée, notamment les cinq régressions ci-dessus. La passe 3 vérifie les commandes visibles du binaire final et répète les scénarios critiques sans modifier les playlists réelles.

### Passe 2 — suite automatisée avec réseau (première tentative)

Commande : `EASYMUSIC_NETWORK_TESTS=1 swift test`.

Preuve : `.tools/qa-pass2-network.log` — 87 tests exécutés, zéro test ignoré, trois échecs concernant le catalogue. `QAActionTests` passe 9/9 et `RequestedPlaybackTests` passe 5/5. Les cinq régressions de la passe 1 sont corrigées. Les contrôles supplémentaires couvrent fichier local disparu et nouvelle tentative, renommage vide, export partiel conservant les originaux, volume restauré après muet.

Les échecs restants sont `CatalogCoherenceLiveTests.testAllGenreTilesResolveOnlyToAlbumsWithTheSelectedGenre` (catalogue indisponible), et `LiveSourceTests.testHomeMixesAndPlaylistTracks` (3 sélections au lieu de 4, puis liste indisponible). L’agent cohérence a reproduit un quota Deezer signalé dans un HTTP 200 et prépare un client cadencé avec cache/coalescence. Aucun remplissage avec des sélections sans rapport n’est accepté pour atteindre le seuil du test. Une nouvelle passe réseau est requise après correction.

### Cas signalé : Renaud — trois contrôles réels

L’agent principal a exécuté trois fois `LiveRenaudPlaybackTests.testReportedRenaudTitleResolvesDownloadsAndProducesPlayableAudio`, avec téléchargement dans un dossier temporaire supprimé après test. Les journaux `.tools/renaud-pass1.log`, `.tools/renaud-pass2.log`, `.tools/renaud-pass3.log` montrent chacun un succès : 15,676 s, 14,563 s, 14,741 s. Les fichiers obtenus durent 217,42 s ou 217,83 s, sont lisibles par AVFoundation et contiennent uniquement de l’audio. L’attribution « Sur les motifs de Water Is Deep » ne bloque plus la recherche, mais les variantes live/reprise non demandées restent rejetées au test.

### Passe 3 — interface isolée (29 octobre 2026)

Binaire `EasyMusicQA.app`, mêmes composants produit pour les commandes ci-dessous, bibliothèque injectée dans `/Users/k2r59/Library/Caches/EasyMusic-QA/Data` ; mise à jour automatique désactivée uniquement dans ce binaire QA. Trois WAV synthétiques d’une minute, listes dédiées. Aucune vraie playlist utilisateur modifiée. Les derniers changements de source des classements et les libellés « Chapitre » restent à contrôler sur le binaire final.

Contrôles réalisés par l’interface native :

- Créer une liste : bouton désactivé si nom vide ; création « QA — Créée » visible, zéro titre et commandes audio/export désactivées.
- Renommer : « QA — Ordre 3, 1, 2 » devient « QA — Renommée » dans l’en-tête et la barre latérale ; ordre conservé.
- Supprimer : annuler la confirmation conserve la liste ; confirmer supprime uniquement la liste de test, puis affiche les trois morceaux dans la bibliothèque.
- Ajouter/retirer : le sélecteur multi-playlists indique l’appartenance ; ajout du morceau 2 dans une autre liste met le compteur à 2 ; filtrage « supprimer » retrouve cette liste ; retrait remet le compteur à 1.
- Couverture : choix du PNG de test via le sélecteur macOS ; image visible dans l’en-tête et la barre latérale. Chemin copié dans `Data/PlaylistArtwork` et persistance JSON vérifiés.
- Export : bouton « Pour Offline Music », dossier QA Exports ; message explicite sur l’import des fichiers et l’absence de synchro automatique avec l’app iPhone. Trois WAV copiés et M3U8 dans l’ordre 3, 1, 2 ; originaux conservés (960044 octets chacun).
- Lecture : clic sur pochette lance Morceau 3, durée 1:00 ; pause/reprise ; aléatoire activé puis désactivé, suivant joue Morceau 1 ; précédent revient au début puis au morceau précédent ; file d’attente 3, 1, 2, clic sur Morceau 2 le lance.
- Lecteur : répétition file/titre/désactivée ; seek avance ; volume 0,8 → 0,7, muet → 0 puis retour 0,7 ; sortie audio ouvre le sélecteur macOS ; plein écran et retour fenêtre ; vue agrandie/fermeture.
- Fiche titre : clic sur nom ouvre volet droit du bon titre, action lecture, extrait distinct et « En local · ≈ 128 kb/s » ; fermeture fonctionne.
- Réglages : sélection MP3 appliquée ; choix du dossier de test confirmé ; format et chemin visibles. Les boutons de mise à jour sont volontairement désactivés dans ce binaire isolé et ne constituent pas une preuve de fonctionnement de Sparkle.
- Import invalide : URL example.com refusée immédiatement avec encadré orange « Import impossible » lisible ; bouton de fermeture fonctionne. Pas de données ajoutées.

Les contrôles visuels ont été réalisés dans CUA avec arbre d’accessibilité et captures. Le sélecteur de sortie audio a seulement été ouvert : aucune sortie matérielle utilisateur n’a été changée.

L’extrait local a ensuite été laissé jouer : durée affichée 0:30, arrêt automatique exactement à 30 secondes, bouton central redevenu « Lire » et aucune piste suivante lancée.

### Suite finale complète

Commande finale de l’agent principal : `EASYMUSIC_NETWORK_TESTS=1 EASYMUSIC_RENAUD_TEST=1 swift test`.

Preuve vérifiée : `.tools/qa-full-final.log`, terminé le 29 octobre 2026 à 11:39:28 — **94 tests exécutés, 0 échec, 0 ignoré**, durée 96,856 secondes. Les 9 tests de régression QA et 5 tests d’intention de lecture passent. Sont inclus les imports publics Spotify/Deezer/YouTube Music, les extraits réels YouTube/SoundCloud, conversion FFmpeg avec lecture AVFoundation, limites de concurrence/fallback, synchronisation, suppression/persistance et les contrôles du catalogue.

Le catalogue a également obtenu trois passes indépendantes à 16/16, selon `docs/COHERENCE-0.4.1.md`. La source officielle de classement est désormais iTunes, explicitement présentée « Top ventes France · iTunes ».

### Vérifications du paquet final

`codesign --verify --deep --strict --verbose=2 dist/EasyMusic-0.4.1.app` : valide. Signature Developer ID Application « Les papas du code » (WN9MHL56A9), runtime renforcé, composants Sparkle validés. Exécutable universel arm64/x86_64. Info.plist : version 0.4.1, build 6, feed HTTPS `https://k2r59.github.io/EsaySoft/easymusic/appcast.xml`, clé Ed25519 présente. La notarisation et la vérification du dernier feed après publication sont à consigner par l’agent principal.

Notarisation Apple acceptée : `0058c11d-1394-4dd6-8372-ceb9e6211224` (journal `.tools/0.4.1-notary.log`). Contrôle indépendant : `spctl --assess --type execute --verbose=2` retourne « accepted / Notarized Developer ID » ; `stapler validate` réussit sur l’application et le DMG. Le feed de staging contient version 6/0.4.1 et signatures Ed25519 du feed et du DMG ; script de préparation terminé sans erreur (`.tools/0.4.1-staged-feed.log`). Rien n’a encore été publié durant ce contrôle.


### Point encore ouvert — liaison de contrôle UI

Après actualisation du binaire QA vers les sources finales (iTunes/Chapitre), l’outil CUA n’a plus réussi à initialiser sa connexion au bureau. Plusieurs appels échouent avant le lancement du nouveau binaire isolé, y compris après réinitialisation du noyau et création d’un nouveau bundle/identifiant : `Computer Use server error -10005: timed out waiting for initialize from codex app-server`. Le processus QA précédemment contrôlé est au repos normal dans la boucle AppKit, selon `.tools/qa-final-startup-sample.txt`. Aucun défaut produit n’est démontré par cet incident de l’outil.

**État actuel : 9/10 catégories vérifiées ; publication encore suspendue.** Restent à constater visuellement sur le binaire final : accueil avec attribution iTunes, recherche/filtres, Livres audio → livre → chapitres → Retour, puis fermeture du volet. Les 94 tests automatisés et les trois passes catalogue réussies couvrent déjà leurs données et logique ; ils ne remplacent pas cette dernière observation de l’interface.

Limites à conserver même après validation finale : le score porte sur cette matrice et les échantillons datés, pas sur la disponibilité perpétuelle de toutes les sources. L’export Offline Music a été contrôlé sur Mac, sans appareil iPhone connecté ; aucune synchronisation automatique n’est promise. Le paquet contient les deux architectures, mais il a été exécuté sur Apple Silicon, pas sur un Mac Intel physique. L’installation Sparkle 0.4.0 → 0.4.1 en production ne peut être observée avant publication ; signatures et protections des opérations en cours ont été vérifiées avant diffusion, puis le feed public et les fichiers diffusés devront être vérifiés après celle-ci.
