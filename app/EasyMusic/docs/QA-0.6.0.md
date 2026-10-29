# Contrôle qualité EasyMusic 0.6.0

Audit du 29 octobre 2026. **QA : 10/10 sur la matrice définie, avec les dix critères validés.** Trois suites de 166 tests, puis une quatrième de 167 tests après la dernière correction, passent sans échec ni test ignoré. Les contrôles de l’interface ont été réalisés dans l’application QA avec une bibliothèque isolée.

Le paquet 0.6.0 / build 8 est signé et notarisé. L’agent QA a vérifié les tickets, le flux de mise à jour et les signatures du flux et du DMG. Aucun défaut bloquant ne reste ouvert dans ce périmètre. L’agent principal peut publier ; l’agent QA n’a effectué aucune publication.

## Matrice de validation

Un critère vaut un point lorsqu’il dispose de preuves pour la version contrôlée. La disponibilité future des services tiers reste hors de cette note.

| # | Critère | Preuves et résultat attendu | État |
|---|---|---|---|
| 1 | Recherche et catalogue | Filtres, genres vérifiés, livres audio et chapitres, classement iTunes attribué, artistes homonymes et albums liés au titre. | PASS : suites complètes, contrôles antérieurs des composants conservés |
| 2 | Correspondance et lecture distante | Même titre, artiste et édition ; audio seul, durée correcte, autre format ou source après échec. | PASS : HLS réel et test 7/12 pouces dans la quatrième suite complète |
| 3 | Copie locale et téléchargement | Réutilisation malgré la ponctuation du catalogue, aucune création de fichier par Lire ou J’aime, téléchargement explicite indépendant. | PASS : tests locaux et réseau, fichier temporaire Renaud lisible |
| 4 | Lecteur et préparation du suivant | Pause, déplacement, extrait de 30 secondes, file mixte, reprise de préparation, annulation, aléatoire et restauration de l’ordre. | PASS : 5 tests PrefetchPlayback, tests RequestedPlayback et interface |
| 5 | Favoris et notes | Cœur et note indépendants, notes de 1 à 5 ou effacement, persistance, partage entre sources compatibles, file Titres aimés. | PASS : 8 tests TrackPreferences et redémarrage QA |
| 6 | Playlists, imports et export | Ajout à plusieurs listes, renommage, suppression, couverture, synchronisation conservant les ajouts, export sans écrasement. | PASS : suites de régression, contrôles précédents des commandes conservées |
| 7 | Informations DJ | BPM et tonalité sourcés, estimations indiquées, valeurs inconnues laissées vides, annulation et invalidation du cache local. | PASS : tests unitaires, FFprobe/FFmpeg/DSP réels, métadonnées Deezer et interface |
| 8 | Interface et commandes | Lecture séparée des détails, cœur, étoiles, sélecteurs lisibles, choix appliqué, fermeture du panneau et des fenêtres contextuelles. | PASS : contrôles CUA du binaire QA reconstruit, transmis par l’agent principal |
| 9 | Régressions répétées | Suites complètes avec réseau et titre signalé ; aucun test échoué ou ignoré ; derniers changements inclus. | PASS : trois suites de 166 tests, puis 167 tests après la dernière correction |
| 10 | Distribution | Version et architectures, signature Developer ID, notarisation, tickets et signatures du flux et du DMG. | PASS : version 0.6.0/build 8, universel, Developer ID, Apple Accepted, tickets et signatures Sparkle |

## Quatre passages complets

Commande : `EASYMUSIC_NETWORK_TESTS=1 EASYMUSIC_RENAUD_TEST=1 swift test`. L’agent QA a relu les résumés de fin et recherché les cas échoués ou ignorés. Horaires Europe/Paris, le 29 octobre 2026.

| Passe | Début | Fin | Durée | Résultat | Journal |
|---|---|---|---|---|---|
| 1 | 14:00:41.638 | 14:03:17.561 | 155,923 s | 166 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.0-final-pass1.log` |
| 2 | 14:07:22.433 | 14:10:03.131 | 160,698 s | 166 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.0-final-pass2.log` |
| 3 | 14:10:18.062 | 14:12:57.838 | 159,776 s | 166 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.0-final-pass3.log` |
| 4 | 14:13:23.289 | 14:15:54.379 | 151,090 s | 167 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.0-final-pass4.log` |

Ces passages représentent **665 exécutions de tests réussies**. Ils couvrent le nouveau lecteur, les préférences, la préparation du suivant, les métadonnées DJ et les régressions existantes. Après les premières passes, le contrôle a trouvé un cas supplémentaire : avec une durée identique, une édition 7 pouces pouvait accepter une édition 12 pouces. La quatrième suite inclut le correctif et le test `testExplicitSevenAndTwelveInchVersionsCannotReplaceEachOther`, qui passe. Cette dernière suite valide les sources finales ; les trois premières documentent les répétitions précédentes.

## Défauts audio reproduits et corrections vérifiées

Le fichier local « Soushkin - 7 Inch Edit » n’était pas reconnu depuis le résultat « Soushkin (7 Inch Edit) ». La comparaison conservait les parenthèses et le tiret. Le rapprochement utilise maintenant la ponctuation normalisée et reconnaît les notations `7 Inch`, `7"` et `7''`, tout en conservant les informations d’édition.

Le flux YouTube M4A de Soushkin présentait aussi une anomalie AVFoundation. Le catalogue et FFprobe indiquaient environ 234 secondes, alors que l’asset, la piste et l’AVPlayerItem prêt annonçaient 467,695 secondes. La sonde QA a confirmé cette différence. Le lecteur essaie désormais le HLS audio et plusieurs formats d’un même candidat. La validation vérifie les pistes et la durée sur l’AVPlayerItem prêt, car un asset HLS peut ne pas exposer ses pistes avant cette étape.

Les recherches, extractions et validations des fournisseurs sont concurrentes. Une sonde isolée a confirmé qu’un résultat YouTube prêt en 25 ms gagne même si l’extraction SoundCloud attend encore 300 ms. Les tâches perdantes sont annulées. Les sources protégées, les aperçus, la vidéo et les versions incompatibles restent rejetés.

La préparation du morceau suivant alimente un cache temporaire de flux. Cliquer sur Suivant réutilise une préparation en cours. L’annulation de cette lecture annule aussi la préparation ; même un résolveur qui retourne ensuite un résultat ne relance pas le lecteur. Le changement d’ordre aléatoire prépare le nouveau suivant. Un échec de préparation laisse la lecture actuelle continuer et permet une nouvelle tentative au passage au titre suivant.

## Mesures de lecture réelle

Les mesures suivantes proviennent de la première suite complète. Le test vérifie la présence d’audio, l’absence de vidéo, la progression du lecteur, la durée et un déplacement au-delà de 45 secondes.

| Titre | Durée AVPlayer | Premier démarrage | Relance avec le flux préparé |
|---|---|---|---|
| Soushkin (7 Inch Edit) | 233,8 s | 8,95 s | 0,36 s |
| Belgium Rave (Original Remastered Mix) | 243,08 s | 8,70 s | 0,36 s |
| Ma Benz | 235,84 s | 5,14 s | 0,37 s |

Le test de file mesure **0,36 seconde** pour passer d’un fichier local au titre distant préparé. Les fichiers de la bibliothèque restent inchangés. Ces chiffres décrivent l’environnement testé : compter environ **5 à 10 secondes au premier accès** dans cet échantillon, puis environ **0,36 seconde quand le flux est déjà préparé**. Un cache vide, une URL expirée ou une source lente peut allonger le délai.

## Préférences et playlists

`TrackPreferencesTests.swift` couvre huit scénarios : chargement d’un ancien JSON sans préférences, persistance, équivalence entre sources et ponctuations, séparation des variantes et artistes, limites des notes, indépendance cœur/note, absence de téléchargement et conservation après ajout puis retrait de deux playlists. Il vérifie aussi que Titres aimés exclut les morceaux seulement notés et fournit sa propre file de lecture.

`PrefetchPlaybackTests.swift` couvre cinq scénarios avec des WAV synthétiques et des résolveurs injectés : reprise d’une préparation en cours, annulation avec résultat tardif, échec silencieux puis nouvelle tentative, changement d’ordre et exclusion de la pré-écoute. Les tests n’accèdent à aucune vraie bibliothèque et ne contactent aucun service externe.

## Contrôles de l’interface

L’agent principal a réalisé ces actions via CUA dans le binaire QA reconstruit et en a transmis les observations à l’agent QA :

- **Sélecteurs** : cadre sombre arrondi de 42 pixels, chevron à droite, fenêtre contextuelle sombre et coche verte. Échap ferme la fenêtre. Dans Sources et réglages, choisir MP3 à la place d’Original actualise la valeur et l’aide affichées.
- **Persistance** : après redémarrage, Soushkin reste aimé et conserve sa note 5/5.
- **Détails et lecture** : cliquer sur un titre ouvre sa fiche sans démarrer le lecteur. Le bouton de lecture à gauche lance Soushkin avec une durée de 3:53. Suivant démarre Belgium Rave avec une durée de 4:03 grâce à sa préparation.
- **Navigation pendant la pause** : après pause de Belgium Rave, ouvrir les détails de Ma Benz conserve Belgium Rave en pause. Cliquer sur la pochette ouvre aussi la fiche sans reprendre la lecture.
- **Ajout à une playlist** : le bouton + ajoute Soushkin à « Playlist test » ; le compteur passe à un titre sans téléchargement.
- **Étoiles et cœur** : noter Ma Benz 5/5 puis recliquer sur la cinquième étoile efface la note. Le cœur ajoute le titre à Titres aimés, qui affiche alors deux morceaux.
- **DJ** : Soushkin affiche environ 156 BPM, source Deezer ; Ma Benz affiche 91,1 BPM. Le code affiche une estimation avec `≈` et sa provenance, et laisse les valeurs inconnues à `—`.

L’agent principal a quitté l’application QA puis déplacé son bundle à la Corbeille après les contrôles. La bibliothèque utilisateur réelle n’a pas servi de fixture.

La relecture du code vérifie que les boutons de détails, de lecture, de pré-écoute, de téléchargement et de préférence ont des actions distinctes. Les contrôles CUA sont la preuve d’exécution des nouvelles commandes ; la compilation seule ne suffit pas à les valider.

## Analyse DJ

Le test réseau relève **156,01 BPM déclarés par Deezer pour Soushkin**, sans analyse audio distante automatique. L’analyse locale réelle passe par FFprobe, FFmpeg puis le traitement numérique du signal. Sur la progression synthétique de référence, elle produit **Do majeur / 8B**, avec la provenance « Estimation · audio ».

Le test confirme que l’analyse ne modifie pas le fichier musical et ne crée aucun fichier d’analyse. Un changement de date de modification inférieur à une seconde, à taille identique, invalide le cache. Les tests couvrent aussi les tonalités Camelot, les rythmes synthétiques, le silence, les valeurs inconnues et l’annulation.

## Distribution finale vérifiée

L’agent QA a effectué ces vérifications indépendantes sur les artefacts finaux de la version 0.6.0, après la quatrième suite et sans changement produit ultérieur :

- `dist/EasyMusic-0.6.0.app` : Info.plist confirme **0.6.0 / build 8**, `local.easymusic.app`, macOS 13.0 minimum et la clé publique Sparkle. Le flux est `https://k2r59.github.io/EsaySoft/easymusic/appcast.xml`.
- `file` confirme les deux architectures **arm64 et x86_64**.
- `codesign --verify --deep --strict --verbose=2` valide l’application et ses composants Sparkle. Signature **Developer ID Application: Les papas du code (WN9MHL56A9)**, runtime renforcé.
- Le journal `.tools/notary-0.6.0.log` confirme **Accepted**, identifiant Apple `fe58764d-1a7e-4ead-a7a8-5a967cc8b3be`.
- `spctl --assess --type execute --verbose=2` retourne **accepted / Notarized Developer ID**.
- `xcrun stapler validate` réussit sur l’application et le DMG. La signature du DMG passe aussi `codesign --verify --strict`.
- `dist/appcast.xml` annonce **8 / 0.6.0**, avec l’URL de la bonne version et la longueur exacte du DMG.
- Les signatures Ed25519 du flux et du DMG ont été vérifiées avec `scripts/verify-update.swift` et la clé publique de l’application. Les deux commandes retournent **Signature valide**. Aucun accès à une clé privée n’a été nécessaire pour ces vérifications.

DMG final : `dist/EasyMusic-0.6.0-universal.dmg`, **134 838 151 octets**. SHA-256 :

```text
8bbd42e0cfdcadbb277a19d7c35c4fe89ac3fcdcb8238b0e082f2db9371922cb
```

**Décision QA : 10 critères vérifiés sur 10.** La note porte sur cette matrice, les contrôles documentés et les échantillons datés. Après publication, l’agent principal doit contrôler le flux public et comparer le fichier distribué au paquet validé. L’installation Sparkle en production reste une vérification après diffusion.

## Limites

- Le contrôle porte sur les actions, données et échantillons datés de cette matrice. Les catalogues, quotas et flux externes peuvent changer après publication.
- Les délais mesurés dépendent du réseau et de l’état du cache. La préparation accélère les transitions lorsqu’une source accessible est trouvée ; elle ne garantit pas une lecture instantanée de tout titre.
- Les BPM et tonalités issus de l’analyse sont des estimations. Les tests synthétiques et le consensus entre segments ne garantissent pas une identification exacte pour chaque morceau.
- Les tests audio vérifient les formats, pistes, durées et la progression AVPlayer. Ils ne mesurent pas la qualité acoustique.
- L’export pour Offline Music a été vérifié sur Mac ; aucun iPhone connecté ni synchronisation automatique avec cette application n’a été validé.
- Les essais d’exécution ont lieu sur Apple Silicon. L’architecture Intel est présente dans le paquet, mais aucun Mac Intel physique n’a servi aux essais.

