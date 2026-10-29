# Contrôle de cohérence : EasyMusic 0.6.1

Audit final du 29 octobre 2026, clos après la troisième suite générale à 15:49:37. Relecture indépendante de la sélection audio, des préparations de lecture, des crédits artistes, de la récupération de playlist, des tests associés et des trois journaux finaux. Le code et le runtime corrigés sont ceux utilisés pour ces trois passes. La signature, la notarisation et la publication relèvent du contrôle de distribution.

**Verdict final : 10/10 sur les dix critères définis ci-dessous.** Les trois passes exécutent les mêmes **222 tests uniques**, tous réussis, sans test ignoré : **666 exécutions** au total. Aucun défaut bloquant n’a été constaté dans ce périmètre. Les quatre titres récupérables et le refus du Medley ambigu ont été reproduits à chaque passe. Cette note évalue aussi le refus correct d’un résultat insuffisamment prouvé ; elle ne garantit ni une latence constante ni l’identification parfaite de tous les enregistrements.

## Matrice de contrôle

| Nº | Critère | Preuves vérifiées | État |
| --- | --- | --- | --- |
| 1 | Les catégories et sélections respectent leur thème | À chaque passe, 25 catégories et 74 albums vérifiés par leurs genres ; livres audio, Jazz et Rock distincts ; playlists d’accueil soumises aux contrôles de contenu | PASS |
| 2 | Classements, personnalisation et fiches conservent une origine explicable | Flux iTunes attribué ; recommandations Renaud vérifiées ; classement titre/artiste et relations de catalogue désambiguïsées | PASS |
| 3 | L’identité du morceau reste cohérente malgré des crédits abrégés | Principal entier, invités confrontés entre titres et métadonnées, ordre des invités toléré, homonymes et versions contradictoires refusés ; enrichissement borné ; déduplication locale inchangée | PASS |
| 4 | Chaque profil fournit seulement un flux audio admissible | Sélection audio seule ; DRM, aperçu, vidéo et format incompatible rejetés ; contrôle du lecteur maintenu | PASS |
| 5 | Un échec rapide conserve les autres possibilités de lecture | 13 tests de profil : réseau, format, durée et validation AVPlayer provoquent le repli complet ; annulation propagée | PASS |
| 6 | La préparation au survol reste silencieuse et réutilisable | Temporisation de 250 ms ; aucune lecture avant clic ; transfert de la tâche au clic sans seconde résolution | PASS |
| 7 | Annulation et préparation du suivant restent cohérentes | Sortie du survol, clic annulé, résultat tardif, échec silencieux, ordre aléatoire et préécoute couverts par huit tests de préparation | PASS |
| 8 | Lecture distante et téléchargement gardent des résultats distincts et vérifiables | Le streaming n’ajoute pas de fichier local ; quatre téléchargements complets avec JPEG dans des dossiers d’essai neufs ; Medley ambigu refusé ; repli pochette borné | PASS |
| 9 | Les informations DJ gardent leur provenance et leur état inconnu | 12 tests DJ : BPM Deezer réel, tags, 24 tonalités Camelot, abstention, analyse locale réelle et invalidation du cache | PASS |
| 10 | Le dernier état passe trois régressions complètes | Mêmes 222 cas aux trois passes ; les 183 cas initiaux de 0.6.1 sont conservés, avec 39 nouveaux contrôles | PASS |

## Trois passes finales

Les résultats ont été recomptés depuis les lignes individuelles XCTest. Chaque journal contient sa clôture `All tests passed` ; les ensembles de noms de tests sont identiques. Les horaires sont ceux inscrits dans les journaux.

| Passe du 29 octobre 2026 | Début | Fin | Réussites | Échecs / ignorés | Durée totale |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | 15:40:09,242 | 15:43:24,024 | 222/222 | 0 / 0 | 194,782 s |
| 2 | 15:43:26,845 | 15:46:29,947 | 222/222 | 0 / 0 | 183,103 s |
| 3 | 15:46:32,443 | 15:49:37,152 | 222/222 | 0 / 0 | 184,709 s |

Journaux de livraison : `.tools/qa-0.6.1-release-pass1.log`, `.tools/qa-0.6.1-release-pass2.log` et `.tools/qa-0.6.1-release-pass3.log`. La comparaison avec les anciennes suites `qa-0.6.1-final-pass*.log` ne révèle aucune suppression de test. Ces anciennes suites de 183 cas précédaient les correctifs de playlist, de pochettes et de notifications ; elles ne servent pas de validation de l’état final. Les messages de diagnostic système présents dans les journaux ne sont pas assimilés à des échecs XCTest.

## Extraction et sélection audio

Le script `prepare-ytdlp.py` épingle yt-dlp **2026.10.26**, récupère son archive depuis la publication GitHub du projet et vérifie sa somme SHA-256. Le calcul indépendant sur l’archive locale correspond à la valeur attendue : `20d98fa608998eff87d1d35a6e9fb65e4b874639a6cc89addc19da3becde3ef1`. Le moteur privilégie l’exécutable déjà déployé dans les ressources de l’application. Le préchauffage appelle seulement `--version`, sans requête de catalogue ou d’audio.

Pour un hôte YouTube reconnu, la première extraction utilise le client `visionos` et omet `initial_data`, DASH et les sous-titres traduits. Cette tentative dispose de 5 secondes au maximum, dans le budget global de résolution. Après un échec de requête, un format inadmissible, une durée incompatible ou un refus par AVPlayer, le même candidat est réessayé avec le profil complet, plafonné à 15 secondes. Une annulation arrête ce parcours. SoundCloud et les autres services utilisent directement le profil complet.

Les deux profils utilisent `--skip-download` et `--dump-single-json`, sans chemin de sortie musical. Chaque branche de sélection impose `vcodec=none`. Le filtrage refuse les DRM déclarés, les aperçus, les formats contenant une vidéo, les codecs incompatibles et les URL non HTTPS. La validation AVPlayer confirme la présence d’audio, l’absence de vidéo et une durée cohérente lorsque la durée attendue est exploitable. HLS reste prioritaire pour éviter le problème de durée doublée observé avec certains flux M4A YouTube.

Le seuil de correspondance distant reste à 0,85. Les crédits d’invités sont séparés du titre musical et confrontés aux métadonnées. Leur ordre peut varier, mais le principal et un invité explicitement contradictoire ne sont pas interchangeables. Un suffixe de version après `featuring` reste dans le titre. Les protections couvrent notamment remix, live, Medley, Extended/Radio et la contradiction explicite entre éditions 7 et 12 pouces. La tolérance de durée des candidats reste de 20 secondes ou 12 % de la durée attendue, selon la valeur la plus grande. La copie locale conserve son rapprochement plus strict, avec au plus 2 secondes d’écart.

Les recherches SoundCloud et YouTube concourent jusqu’à obtenir un flux validé. La branche perdante est annulée. Le budget nominal global reste de 55 secondes ; les opérations respectent aussi leurs plafonds individuels. Les sorties des processus restent en mémoire et les deux canaux de sortie sont lus simultanément. La fermeture ou l’annulation termine le processus associé.

## Préparation et comportement du lecteur

Le survol du bouton de lecture attend **250 ms** avant de préparer le flux. Un passage plus court de la souris ne lance pas cette préparation. Le lecteur courant, la sélection affichée et la bibliothèque restent inchangés. Au clic, `requestPlayback` transfère la tâche correspondante avant de réinitialiser l’ancienne demande ; la sortie du survol qui suit le clic ne l’annule donc pas.

Le survol et la préparation automatique du prochain morceau partagent un seul emplacement de préparation dans le Store. Quitter le survol annule sa préparation et rétablit celle du prochain morceau, lorsqu’elle s’applique. La préparation automatique attend une seconde. Elle suit l’ordre réel de la file après activation ou désactivation de la lecture aléatoire. Une préécoute ne prépare pas le titre complet suivant.

Les tests vérifient aussi l’annulation pendant le transfert au clic et le rejet d’un résultat retourné après cette annulation. L’échec d’une préparation reste silencieux et n’interrompt pas le morceau courant ; le clic peut réessayer. Une lecture déjà demandée empêche le survol de lancer une préparation concurrente. Ces parcours n’utilisent pas le moteur de téléchargement et n’ajoutent pas de morceau à la bibliothèque.

Le cache conserve au maximum 64 flux, pendant 15 minutes au plus, en tenant compte de l’expiration des URL signées. Une source exclue après erreur n’est pas réutilisée. La fiche du titre conserve le sélecteur **Qualité audio** ; la recherche et les lignes principales ne le répètent plus. Ce dernier point est une vérification du code d’interface ; le contrôle visuel de l’application relève du rapport QA général.

## Mesures de lecture réelles

Les durées ci-dessous proviennent des essais réseau des trois passes. Le premier démarrage de chaque cas inclut sa résolution ; les relances utilisent le cache de flux. Ces chiffres décrivent l’environnement du test et ne sont pas des engagements de performance.

| Morceau | Durée audio contrôlée | Premier démarrage, minimum–maximum | Relance, minimum–maximum |
| --- | ---: | ---: | ---: |
| Soushkin (7 Inch Edit) | 233,80 s | 3,133–3,464 s | 0,368–0,375 s |
| Belgium Rave (Original Remastered Mix) | 243,08 s | 2,815–3,304 s | 0,356–0,367 s |
| Ma Benz | 235,84 s | 2,011–2,557 s | 0,362–0,369 s |

Ces cas vérifient aussi la poursuite de la lecture après un déplacement à 45 secondes. La résolution du titre Renaud via SoundCloud prend 2,19 à 4,15 secondes, avec une durée audio de 208,61 secondes. Le témoin YouTube est lu au-delà de 45 secondes avec une durée totale de 634,566 secondes. Le prochain titre déjà préparé démarre en 0,367 à 0,372 seconde, sans téléchargement dans la bibliothèque.

## Playlist et téléchargements complets

Le [diagnostic Rap 90 2k FR](PLAYLIST-RECOVERY-0.6.1.md) a identifié cinq titres manquants parmi les 61 exposés par l’import public. Les résultats abrégés masquaient certains crédits. L’import conserve désormais les noms séparés sans couper les noms comportant une virgule ordinaire ou une esperluette. Après les candidats déjà fiables, le moteur peut inspecter deux résultats rejetés plausibles par service, pendant 10 secondes au maximum chacun, puis applique les mêmes exigences de correspondance et de durée.

Chaque suite finale refait de vrais transferts dans un dossier neuf et confirme quatre fichiers complets : Medley Thugs / Interlude, 16'30 Contre la censure, Beat de Boul est dans la sono et C’est donc ça nos vies. Tous sont lisibles, contiennent de l’audio sans vidéo de lecture et possèdent une pochette JPEG. Le cinquième titre, J’avance pour ma familia en version Medley, reste refusé : les métadonnées des sources examinées ne suffisent pas à confirmer cette version. Les 56 fichiers de la bibliothèque utilisateur n’ont pas été complétés par ces essais isolés.

Les essais ont aussi révélé une erreur de finalisation des pochettes après transfert réussi. Le runtime FFmpeg corrigé active PNG/zlib et le filtre `mjpeg2jpeg` ; l’export conserve une pochette JPEG. Si seule cette étape optionnelle échoue encore, un essai borné conserve l’audio et les tags, avec les contrôles audio et DRM maintenus. Une image de pochette attachée n’est pas comptée comme une vidéo animée.

La passe ciblée instrumentée a mesuré 11,43 à 28,05 secondes pour recherche, téléchargement intégral, conversion et finalisation des quatre morceaux. Le titre le plus long dure près de 17 minutes. Ces mesures sont distinctes du délai de démarrage en streaming présenté plus haut.

## Catalogue et informations DJ conservés

Les trois passes retrouvent 74 albums vérifiés dans 25 catégories. Les livres audio proposent notamment des histoires de P’tit Loup et Anatole ; Jazz et Rock renvoient des albums distincts. L’accueil conserve des playlists vérifiées pour Pop, Rap, Rock, Electro et Jazz. Chanson française, Soul et Latino restent omis dans cet échantillon lorsqu’aucun résultat examiné ne satisfait les critères.

Le classement conserve l’attribution **Top ventes France · iTunes** et le rapprochement exact des titres et artistes avec Deezer. Les recherches et écoutes alimentent une personnalisation bornée. Les tests des homonymes et des relations de fiches sont toujours présents. Le détail de ces règles et leurs sources figure dans [l’audit 0.6.0](COHERENCE-0.6.0.md).

Les 12 tests DJ réussissent aux trois passes. Soushkin conserve **156,01 BPM déclarés par Deezer**, sans analyse distante automatique. L’intégration FFprobe → FFmpeg → analyse native retrouve **Do majeur, 8B** dans le fichier synthétique, sans fichier d’analyse ajouté. Ce contrôle prend 0,99 à 1,06 seconde et confirme l’invalidation du cache après changement de date de modification. Les valeurs absentes ou insuffisamment fiables restent inconnues ; l’accélération du lecteur n’ajoute aucune estimation musicale.

## Portée et limites

- Les correspondances reposent sur les métadonnées et la durée, sans empreinte audio. Des crédits ou versions incomplets ne permettent pas de garantir l’identité absolue d’un enregistrement.
- Les résultats de catégories et playlists sont contrôlés sur des échantillons. Les catalogues publics et leurs classements peuvent évoluer après ces essais.
- Le survol prépare une ressource distante : il peut provoquer des requêtes réseau et une mise en mémoire tampon même si l’utilisateur ne clique pas. Il n’ajoute aucun fichier musical à la bibliothèque. Les caches internes éventuels du système ne sont pas couverts par cette affirmation.
- Un flux peut expirer, être retiré ou devenir inaccessible entre préparation et lecture. Les exclusions et replis restent disponibles, avec un délai dépendant du réseau et du service.
- Les mesures rapides concernent les cas et l’environnement observés. Une première ouverture sur un autre Mac, un accès lent ou le recours au profil complet peuvent prendre plus longtemps.
- Les BPM déclarés et tonalités estimées conservent les limites de l’audit 0.6.0 : données tierces parfois erronées, extraits courts, morceaux modulants ou non tonals et absence de validation sur un corpus professionnel annoté.
- Cette note évalue les dix critères de la matrice. L’ouverture du paquet signé sur un autre Mac et la distribution de la mise à jour exigent leurs propres contrôles.

Empreintes SHA-256 des sources relues : `AudioStreaming.swift` = `6f0ed058a12de4667cad1fdfe94bf44e1a6931e15619a76b272cebab754dc8e8` ; `Store.swift` = `20b43a472caa7f7561ccd105180b34f2f53dfac35305d3bc54452dc95354be4f` ; `Models.swift` = `35e249dc7d5593ba941bb9f10168222693a51ec3e8e6ed27970f5c6930026021` ; `AudioDownload.swift` = `6eb9624ae896a193ea2dfef1a7173c453ef85dfdb30d706519d70b8d9409c79e`.
