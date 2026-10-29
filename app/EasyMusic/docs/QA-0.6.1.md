# Contrôle qualité EasyMusic 0.6.1

Audit du 29 octobre 2026. **QA : 10/10 sur les dix critères définis.** Les trois suites complètes sur le code figé passent chacune **222 tests**, sans échec ni test ignoré, soit **666 exécutions réussies**. Elles incluent les notifications, les contre-exemples de correspondance, les flux réels et la récupération des titres accessibles. La dernière passe ciblée préalable réussit aussi 66/66 tests. Le paquet final est signé, notarisé et vérifié ; aucun défaut bloquant ne reste ouvert dans ce périmètre.

Cette version réduit le délai de préparation des flux et réserve le format et le débit audio au panneau de détails. Elle remplace aussi le bandeau global par une notification flottante et l’avertissement d’import incomplet par une icône avec explication au survol ou au clic. Le contrôle porte sur les sources de la version **0.6.1 / build 9**. L’agent principal a effectué les essais d’interface dans une application QA avec une bibliothèque isolée. L’agent QA a relu le code, les journaux et les mesures, puis ajouté les tests du profil rapide et des notifications. Aucun essai n’a modifié la bibliothèque utilisateur réelle.

## Matrice de validation

Un critère vaut un point lorsqu’il dispose de preuves pour la version contrôlée. Les régressions communes avec la version précédente sont documentées dans [QA-0.6.0.md](QA-0.6.0.md) et rejouées dans les trois suites complètes.

| # | Critère | Preuves | État |
|---|---|---|---|
| 1 | Recherche et catalogue | Filtres, genres, livres audio et chapitres, classement iTunes attribué, homonymes et relations titre/artiste/album ; tests réseau répétés. | PASS |
| 2 | Correspondance et résolution audio | Streaming et profil rapide vérifiés ; treize tests contradictoires réussis, crédits principaux, invités et suffixes de version contrôlés. Une version Medley non confirmée reste refusée. | PASS |
| 3 | Copie locale et téléchargement | Cas locaux, conversion et Renaud ; récupération réelle de quatre titres supplémentaires, fichiers complets lisibles et audio seul. Le cinquième titre ambigu est refusé. | PASS |
| 4 | Lecteur et préparation | Pause, déplacement, extrait de 30 secondes, file mixte, annulation, ordre aléatoire ; préparation du suivant et au survol. Huit tests PrefetchPlayback, tests RequestedPlayback et interface QA. | PASS |
| 5 | Favoris et notes | Persistance, cœur et note indépendants, notes de 1 à 5 ou effacement, rapprochement entre sources compatibles et file Titres aimés. Huit tests TrackPreferences rejoués. | PASS |
| 6 | Playlists, import et export | Ajout à plusieurs listes, renommage, suppression, couvertures, conservation du lien d’origine, synchronisation et export sans écrasement. Suites de régression. | PASS |
| 7 | Informations DJ | Provenance du BPM et de la tonalité, estimations signalées, inconnues laissées vides, cache invalidé après modification. Tests Deezer, FFprobe, FFmpeg et analyse locale réelle. | PASS |
| 8 | Interface et commandes | Listes et détails QA061, puis trois lancements QA pour les toasts, l’icône d’import, le bouton Réessayer, la navigation et l’expiration des confirmations. Limite du survol natif précisée ci-dessous. | PASS |
| 9 | Régressions répétées | Trois suites finales de 222 tests, toutes réussies sans test ignoré, après gel des sources et reconstruction du runtime FFmpeg. | PASS |
| 10 | Distribution | Version 0.6.1/build 9 universelle ; 104 composants natifs yt-dlp vérifiés, runtime exécutable, Apple Accepted, tickets valides, signatures du flux et du DMG vérifiées. | PASS |

## Trois passages complets

Ces passages valident le code final, y compris les notifications, l’avertissement d’import, les crédits multiples, les pochettes et le runtime FFmpeg reconstruit.

Commande : `EASYMUSIC_NETWORK_TESTS=1 EASYMUSIC_RENAUD_TEST=1 EASYMUSIC_PLAYLIST_RECOVERY=1 swift test`. L’agent QA a compté indépendamment les 222 cas réussis de chaque journal et vérifié l’absence de cas échoué ou ignoré. Horaires Europe/Paris, le 29 octobre 2026.

| Passe | Début | Fin | Durée des tests | Résultat | Journal |
|---|---|---|---|---|---|
| 1 | 15:40:09.242 | 15:43:24.024 | 194,754 s | 222 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.1-release-pass1.log` |
| 2 | 15:43:26.845 | 15:46:29.947 | 183,072 s | 222 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.1-release-pass2.log` |
| 3 | 15:46:32.443 | 15:49:37.152 | 184,682 s | 222 tests, 0 échec, 0 ignoré | `.tools/qa-0.6.1-release-pass3.log` |

La passe ciblée finale de 66 tests réussit dans `.tools/playlist-061/recovery-final.log`, de 15:37:42.256 à 15:38:58.812. Les trois anciennes suites de 183 tests, conservées dans `.tools/qa-0.6.1-final-pass{1,2,3}.log`, concernent l’état antérieur aux notifications et à la récupération de playlist ; elles ne remplacent pas les suites finales ci-dessus. Les journaux contiennent des diagnostics système CoreData/Contacts ; ils ne correspondent à aucun échec de test.

## Délai de lecture mesuré

Les mesures réelles incluent la résolution du flux et le démarrage d’AVPlayer. Chaque passe vérifie la présence d’audio, l’absence de vidéo, la durée, la progression du lecteur et un déplacement au-delà de 45 secondes. Le cache de flux est vide au premier accès de chaque scénario.

| Titre | Durée AVPlayer | Premier accès, passe 1 | Passe 2 | Passe 3 | Relance préparée, les trois passes |
|---|---|---|---|---|---|
| Soushkin (7 Inch Edit) | 233,8 s | 3,46 s | 3,41 s | 3,13 s | 0,37 s |
| Belgium Rave (Original Remastered Mix) | 243,08 s | 3,30 s | 2,88 s | 2,81 s | 0,36 à 0,37 s |
| Ma Benz | 235,84 s | 2,56 s | 2,01 s | 2,21 s | 0,36 à 0,37 s |

Le passage au prochain morceau préparé prend **0,37 / 0,37 / 0,37 seconde** dans les trois suites. Les vérifications de fichiers confirment l’absence de téléchargement dans la bibliothèque pendant ces scénarios.

Le premier accès mesuré passe donc à environ **2 à 3,5 secondes** sur cet échantillon. La première suite 0.6.0 mesurait 8,95 secondes pour Soushkin, 8,70 secondes pour Belgium Rave et 5,14 secondes pour Ma Benz. Ces essais ont eu lieu à des moments différents sur les services publics : ils montrent le gain observé, sans isoler toutes les variations réseau.

## Runtime yt-dlp et profil rapide

Le profilage sépare le coût du lancement de yt-dlp de celui du service distant. Les fichiers `.tools/latency-061/timings.json` et `.tools/latency-061/expanded/timings.json` donnent les résultats suivants pour la même version yt-dlp **2026.10.26** :

| Opération | Ancien exécutable monofichier | Runtime déployé |
|---|---|---|
| `--version` | 2,549 s | 0,252 s |
| Recherche | 3,238 s | 0,996 s |
| Extraction avec le profil complet | 6,965 s | 2,487 s |
| Extraction avec le profil rapide retenu | Profil complet ci-dessus | 1,411 s |

Le script de préparation vérifie la somme SHA-256 de l’archive officielle avant extraction. Il rétablit les liens du framework Python après comparaison des copies binaires, puis le script de signature signe les composants Mach-O, le framework et le lanceur. Le paquet copie le runtime complet, y compris `_internal`. La recherche d’exécutable privilégie ce chemin embarqué et refuse les répertoires.

L’audit du runtime officiel a trouvé les deux architectures arm64 et x86_64 dans ses composants natifs et aucune dépendance absolue à Homebrew ou au dossier du projet. Un lancement indépendant depuis `/private/tmp`, avec `PATH=/usr/bin:/bin`, retourne la version attendue. Pour une première copie signée Developer ID, l’agent principal rapporte un essai ayant dépassé 10 secondes, suivi de **0,999 / 0,222 / 0,236 seconde**, tous les essais suivants terminés avec le code 0. L’origine du premier délai n’est pas établie ; le contrôle macOS initial est une hypothèse. Le contrôle indépendant du paquet final notarisé donne ensuite **0,377 / 0,220 / 0,220 seconde**, comme détaillé dans la vérification de distribution.

Le profil rapide s’applique aux hôtes YouTube identifiés par leur nom complet. Il demande l’audio HLS via `visionos`, avec une limite de cinq secondes pour l’extraction. Une erreur de lecture, un format incompatible, une durée incorrecte ou un échec de validation AVPlayer déclenche le profil complet du même candidat, limité à quinze secondes. La durée globale reste bornée. Les tests vérifient que SoundCloud et les autres fournisseurs conservent le profil complet, et que les domaines ressemblant à YouTube ne reçoivent pas le profil rapide.

La sélection conserve les exclusions de vidéo, DRM et aperçus. Les formats issus d’une extraction doivent toujours passer la validation du lecteur. Une annulation pendant la lecture des métadonnées ou la validation interrompt la résolution sans repli. Même un résultat de métadonnées reçu après annulation ne peut pas lancer la validation ou la lecture.

## Préparation au survol

Au lancement de l’application, `warmUpRuntime()` exécute seulement `--version` pour amorcer le runtime local. Le survol du bouton de lecture attend 250 millisecondes avant de préparer le flux. Cette préparation partage un seul emplacement avec le prochain morceau de la file.

Les tests ajoutés à PrefetchPlayback vérifient que :

- le survol laisse le lecteur arrêté et n’ajoute ni fichier ni téléchargement ; un clic reprend la préparation en cours sans seconde résolution ;
- sortir du bouton annule la préparation, avant ou après son démarrage ; une lecture déjà demandée reste prioritaire sur un nouveau survol.

Les tests précédents continuent à vérifier le transfert vers Suivant, l’annulation d’un résultat tardif, le repli après échec, l’ordre aléatoire et l’exclusion de la pré-écoute. Les fixtures sont des WAV synthétiques avec des résolveurs injectés.

## Contrôles de l’interface

L’agent principal a reconstruit l’application QA061 avec le runtime Developer ID embarqué et réalisé les contrôles CUA suivants :

- **Listes** : les lignes de la bibliothèque locale et d’une playlist importée n’affichent plus le débit ni le format.
- **Détails** : le panneau d’un titre local conserve `En local · WAV · ≈ 128 kb/s`. La relecture du code confirme que le format et `bitrateLabel` sont affichés dans TrackDetailsView.
- **Lecture** : Soushkin démarre avec une durée affichée de 3:53. Suivant lance Belgium Rave avec une durée de 4:03 en réutilisant sa préparation.

Ces observations ont été transmises par l’agent principal. L’agent QA n’a pas effectué un second pilotage simultané de l’interface. Les commandes inchangées restent couvertes par les tests de régression et les contrôles antérieurs détaillés dans le rapport 0.6.0.

## Notifications validées

L’audit a relevé que deux téléchargements simultanés pouvaient remplacer une erreur par une confirmation de réussite. Une nouvelle recherche effaçait aussi le message global. Enfin, la classification par mots-clés traitait certains échecs comme des informations, notamment un flux inaccessible ou un fichier local disparu.

Le nouveau modèle `MusicNotifications` conserve les erreurs jusqu’à leur fermeture, les place avant les confirmations et déduplique les erreurs identiques encore présentes. Les confirmations successives partagent un seul emplacement. Chaque notification a un identifiant ; l’expiration ne peut retirer que la confirmation actuellement affichée. Le téléchargement publie explicitement une erreur comprenant le titre concerné. Effacer `notice` pendant la navigation laisse la file de notifications intacte.

L’agent QA a ajouté **12 tests** dans `MusicNotificationTests.swift`. Ils couvrent les ordres de fin échec/réussite, deux téléchargements échoués, les erreurs identiques, une nouvelle tentative réussie, la navigation, les erreurs sans mot-clé, un ancien minuteur, l’échec de sauvegarde et le fichier local absent. L’avertissement d’import est aussi vérifié après rechargement de la bibliothèque. Un témoin positif contrôle les téléchargements réussis intitulés « Erreur » et « Impossible » : ils produisent une confirmation qui expire. Le type du message est explicite, sans classification par mots-clés. Les fixtures sont isolées et les transferts simulés ; aucune connexion à un catalogue n’est nécessaire.

Les onze premiers tests passent dans la suite ciblée de 46 tests exécutée par l’agent cohérence, dont l’agent QA a relu le journal `.tools/playlist-061/matching-tests.log`. La suite commence à 15:17:50.528 et termine à 15:17:50.791 ; aucun échec. Les **12 tests finaux passent** ensuite dans `.tools/playlist-061/recovery-pass2.log`, puis dans la passe ciblée finale et dans chacune des trois suites complètes.

L’agent principal a contrôlé la dernière interface via CUA sur trois lancements QA. L’icône d’import reste à droite de la barre d’actions, avec ou sans le panneau de détails. Sa fenêtre contextuelle s’ouvre vers la gauche, reste dans la fenêtre et se ferme par le bouton X ou Échap. Le bandeau d’import a disparu.

Un téléchargement passant par `enqueue`, avec un transfert simulé indisponible, produit un toast orange et un bouton Réessayer orange. L’explication demeure accessible dans l’aide du bouton ; aucun texte d’erreur ne modifie la hauteur de la ligne. Le toast reste présent après navigation et nouvelle confirmation. Sa fermeture révèle la confirmation suivante, puis sa disparition automatique après cinq secondes a été observée. Le détail du fichier conserve WAV et environ 128 kb/s ; les listes restent sans format ni débit. L’agent principal a quitté l’application QA après ces contrôles.

Le survol natif n’a pas été exécuté par CUA : les commandes disponibles n’exposent pas de déplacement de pointeur seul. La suspension du minuteur pendant le survol ou le focus clavier reste à distinguer des contrôles effectivement exécutés. L’ouverture au clic fournit l’accès contrôlé à l’avertissement.

## Contre-exemples de correspondance corrigés

L’agent cohérence a reproduit les échecs sur les cinq titres signalés d’une playlist Spotify : l’import expose 61 titres, mais les crédits multiples des morceaux manquants sont mal rapprochés des résultats de recherche. La correction conserve le nom complet de l’artiste principal et enrichit les candidats plausibles avec leurs métadonnées avant le transfert.

L’agent QA a ajouté treize tests dans `MatchingAdversarialTests.swift` : artiste principal et invité inversés, invité contradictoire dans les crédits ou seulement dans le titre, invité seul, homonyme, nom contenant `&` ou une virgule simple, marqueurs live/remix/medley et mot « Featuring » appartenant au vrai titre. Un témoin positif vérifie que les mêmes invités dans un autre ordre restent compatibles lorsque les crédits structurés concordent. Deux tests croisent les preuves quand l’invité figure seulement dans le titre d’un côté et dans la liste des artistes de l’autre.

Le premier passage contradictoire du 29 octobre à 15:20:44 donne **6 tests réussis et 4 échecs**, journal `.tools/playlist-061/adversarial-tests.log`. Le candidat « Notre monde featuring Léa » sans métadonnées d’invité obtenait 1 contre une cible avec Nora : c’était un faux positif. Les crédits textuels « White & Spirit feat. IAM » et « Tyler, The Creator feat. Kali Uchis », ainsi que les mêmes invités dans un ordre différent, étaient rejetés avec un score de 0 : c’étaient trois faux négatifs.

Ces quatre défauts sont corrigés dans la passe ciblée suivante, **56/56 tests réussis**, journal `.tools/playlist-061/matching-tests-pass2.log`. Les deux cas croisant titre et liste d’artistes, ajoutés ensuite, échouent avec un score de 1 dans `.tools/playlist-061/recovery-pass1.log`. La correction rapproche désormais les preuves d’invités des titres et des crédits structurés. Les **12 tests contradictoires passent** dans `.tools/playlist-061/recovery-pass2.log`, à 15:27:46.524.

Un dernier contre-exemple vérifie que « Notre monde featuring Nora - Extended Mix » conserve son suffixe de version après retrait du crédit invité. Il refuse la version courte de même durée, accepte la même version et refuse un autre titre aux crédits identiques. Les **13 tests finaux passent** dans la suite ciblée de 66 tests, puis dans les trois suites complètes de 222 tests.

L’inspection supplémentaire intervient après les candidats déjà assez fiables et porte sur deux candidats au maximum par service, avec une limite de dix secondes chacun. Elle utilise `StreamingProcess`, qui interrompt le processus lors de l’annulation. Le rapprochement local `sameRecording` conserve ses contraintes précédentes.

## Récupération de la playlist signalée

L’import réel de « Rap 90 2k FR » expose **61 titres**. Le second essai ciblé de récupération, dans `.tools/playlist-061/recovery-pass2.log`, confirme quatre fichiers M4A complets et un refus pour une version non confirmée. Le test vérifie la lisibilité AVFoundation, la présence de pistes audio, l’absence de vidéo et un écart de durée inférieur à vingt secondes.

| Titre | Durée du fichier | Résultat |
|---|---|---|
| Medley Thugs / Interlude | 336,043 s | Audio complet récupéré |
| 16'30 Contre la censure | 1 012,843 s | Audio complet récupéré |
| Beat De Boul est dans la sono | 224,473 s | Audio complet récupéré |
| C’est donc ça nos vies | 312,192 s | Audio complet récupéré |
| J’avance pour ma familia, version Medley | Aucun fichier retenu | Version Medley non confirmée ; refus attendu |

Les premières tentatives de transfert révélaient aussi un échec d’insertion de pochette : l’ancien runtime FFmpeg ne disposait pas de l’encodeur PNG demandé par défaut. La conversion explicite de la miniature en JPEG permet de conserver la pochette et de terminer le fichier audio. Le runtime final corrige aussi la cause à la compilation, avec zlib et `mjpeg2jpeg` activés et une révision de cache portée à 2. L’audit `.tools/ffmpeg-cover-audit.json` confirme les deux architectures et uniquement des dépendances système ; les conversions WebP vers PNG et JPEG produisent des fichiers valides. Le repli sans pochette conserve un audio utilisable lorsqu’un post-traitement optionnel échoue.

Cette passe se termine à **15:28:59.769**, après **73,253 secondes de tests**, avec **35/35 tests réussis**. Un résultat PASS pour le cinquième cas signifie que l’application refuse une version ambiguë ; il ne signifie pas que les cinq titres ont été téléchargés. Les fichiers restent dans les dossiers d’essai `.tools/playlist-061`, hors de la bibliothèque utilisateur.

La passe ciblée finale, puis les trois suites complètes, reproduisent **quatre récupérations et un refus cohérent**. Chaque exécution utilise un nouveau dossier. Les quatre fichiers contiennent une pochette JPEG ; le contrôle des pistes distingue cette image jointe d’une piste vidéo animée.

## Distribution finale vérifiée

L’agent QA a contrôlé les artefacts reconstruits après les trois suites finales. La validation porte sur ce nouveau paquet, avec les notifications, les crédits multiples et le runtime FFmpeg corrigé.

- `dist/EasyMusic-0.6.1.app/Contents/Info.plist` confirme **0.6.1 / build 9**, l’identifiant `local.easymusic.app` et le flux `https://k2r59.github.io/EsaySoft/easymusic/appcast.xml`.
- `lipo -archs` et `codesign --verify --strict` valident l’exécutable EasyMusic, FFmpeg, FFprobe et Node en **x86_64 et arm64**. La relecture des dépendances ne trouve aucun chemin Homebrew ou vers le dossier du projet.
- Les **104 fichiers Mach-O non liés symboliquement** du runtime yt-dlp ont chacun passé la vérification de signature stricte, portent l’identité d’équipe **WN9MHL56A9** et contiennent les deux architectures. Le framework Python passe aussi la vérification profonde et stricte. Le lanceur conserve le runtime renforcé sans droit de désactiver la validation des bibliothèques.
- `codesign --verify --deep --strict` valide l’application finale ; la signature stricte du DMG est aussi valide. L’identité est **Developer ID Application: Les papas du code (WN9MHL56A9)**.
- Apple retourne **Accepted**, identifiant `ed00d940-3f1b-4d70-ac80-915ac4cf536f`, dans `.tools/notary-0.6.1-final.log`. Les tickets de l’application et du DMG passent `xcrun stapler validate`. `spctl` accepte les deux artefacts avec la source **Notarized Developer ID**.
- L’agent QA a exécuté le lanceur embarqué depuis `/private/tmp`, avec un environnement limité à `PATH=/usr/bin:/bin` et `LANG=C.UTF-8`. Les trois appels `--version` retournent **2026.10.26**, code 0, en **0,377 / 0,220 / 0,220 seconde**. Les listes de codecs du FFmpeg livré confirment PNG et `mjpeg2jpeg`.
- Les sondes finales de l’agent principal, relues par l’agent QA, extraient le HLS audio en **1,744 seconde**, puis démarrent AVPlayer en **0,804 seconde**. La durée est **233,8 secondes**, la seule piste est audio, et le déplacement atteint **45,429 secondes**. Preuves : `.tools/latency-061/bundled-final-extraction.json` et `.tools/latency-061/bundled-final-player.log`.
- `dist/appcast.xml` annonce la bonne version, le build 9, l’URL du DMG 0.6.1 et sa taille exacte. L’agent QA a vérifié les signatures Ed25519 du flux et du DMG avec `scripts/verify-update.swift` et la clé publique de l’application. Les deux vérifications retournent **Signature valide**, sans accès à une clé privée.

DMG final : `dist/EasyMusic-0.6.1-universal.dmg`, **137 828 197 octets**. SHA-256 :

```text
e5e68e4b4aa3397b7a5b58d4931acf564e54a70da9328541cc42ffdaf05cc699
```

Empreinte SHA-256 du flux validé :

```text
5506e69adaaaf6459e883b913a43f9da026ee0c8bac1ad49f8676a9ba01e3282
```

**Décision QA : dix critères validés sur dix.** L’agent principal peut publier les artefacts contrôlés. L’agent QA n’a effectué aucune publication. Après diffusion, l’agent principal doit comparer le flux et le fichier publics à ces empreintes. L’installation Sparkle en production reste une vérification après diffusion.

## Limites

- Les délais dépendent du réseau, des services, des caches et des contrôles du système au premier lancement. Le survol réduit l’attente lorsque la préparation a eu le temps d’aboutir ; aucun délai universel n’est garanti.
- Les services publics peuvent limiter les requêtes, changer leurs formats ou retirer des titres. Le repli maintient les contraintes de correspondance ; il ne garantit pas l’accès à tout le catalogue.
- Les essais audio vérifient les formats, les pistes, les durées et la progression du lecteur. Ils ne mesurent pas la qualité acoustique.
- Les essais d’exécution ont lieu sur Apple Silicon. Le runtime contient Intel et Apple Silicon, mais aucun Mac Intel physique n’a servi aux essais.
- Les BPM et tonalités estimés peuvent varier selon le morceau. L’export Offline Music a été contrôlé sur Mac ; aucune synchronisation automatique avec un iPhone n’a été validée.
