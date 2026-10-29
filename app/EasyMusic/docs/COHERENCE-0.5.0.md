# Contrôle de cohérence — EasyMusic 0.5.0

Audit final du 29 octobre 2026, après gel des sources de la version 0.5.0. Les dix critères ci-dessous sont validés : **10/10 sur la grille de cohérence définie**, confirmé par trois suites complètes de 133 tests. Ce résultat décrit les contrôles exécutés, pas une garantie sur tous les contenus futurs des services tiers ni un verdict sur la signature du paquet de distribution.

## Validation finale indépendante

Les trois journaux ont été relus et leurs résultats comptés indépendamment : chaque passe contient les mêmes **133 tests uniques réussis**, **aucun échec XCTest** et **aucun test ignoré**. Les trois exécutions représentent 399 résultats de tests. Les dates et heures ci-dessous reprennent les horodatages de XCTest.

| Passe du 29 octobre 2026 | Début | Fin | Tests réussis | Échecs / ignorés | Durée totale |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | 12:37:42,726 | 12:39:40,884 | 133/133 | 0 / 0 | 118,158 s |
| 2 | 12:39:43,375 | 12:41:47,462 | 133/133 | 0 / 0 | 124,087 s |
| 3 | 12:41:48,778 | 12:43:49,632 | 133/133 | 0 / 0 | 120,854 s |

Preuves : `.tools/qa-0.5.0-final-pass1.log`, `.tools/qa-0.5.0-final-pass2.log`, `.tools/qa-0.5.0-final-pass3.log`. Chaque journal confirme les 25 catégories, 74 albums dont le genre a été vérifié, les livres audio et leurs chapitres, les recommandations Renaud, le classement iTunes, le classement de recherche et la relation du titre vers l’artiste 21 et son album exact. Les titres sélectionnés pour Livres audio, Jazz et Rock restent distincts dans les trois passes.

Le flux Renaud complet de 208,56 secondes est résolu en **6,19 s, 6,41 s et 6,42 s**, sans écriture audio détectée. La piste de test distante poursuit sa lecture après déplacement à 45 secondes lors de chaque passe. Les contrôles locaux vérifient aussi les états du lecteur, l’annulation et l’absence d’ajout automatique à la bibliothèque.

Les journaux contiennent des diagnostics système CoreData concernant une connexion à `contactsd.persistence`. Ils sont distincts des résultats XCTest et n’ont provoqué aucun échec d’assertion dans ces passes ; le rapport ne prétend donc pas que les journaux sont exempts de tout diagnostic système. Aucun fichier source n’a été modifié lors de cette relecture finale.

## Défauts reproduits

1. Les réponses publiques Deezer `/genre/457/artists`, `/genre/129/artists` et `/genre/152/artists` présentaient la même liste (Jul, Ninho, Tiakola…), sans respecter Livres audio, Jazz et Rock. Ces réponses ne servent plus au parcours par genre.
2. La recherche de playlists peut renvoyer des résultats reliés au créateur ou à un seul titre de la liste. Exemple : « Renaud » pouvait proposer « Renaud Capuçon », et « blink » des blind tests. Le seul classement de recherche n'est plus une preuve de cohérence.
3. La première passe automatisée intensive a rencontré la limite Deezer : erreurs JSON avec HTTP 200 après de nombreuses requêtes rapprochées. Une cadence commune, la mutualisation des requêtes identiques, un cache de deux minutes et des reprises sur erreur de quota ont été ajoutés.
4. Le flux Apple Music le plus récent répondait en tests isolés, mais expirait à répétition après le parcours de nombreuses catégories dans le même processus. Cette source n’a pas été validée. Le flux officiel iTunes France, stable dans ce scénario, la remplace avec la mention exacte « Top ventes France · iTunes ». Les ventes iTunes ne sont pas présentées comme des écoutes Apple Music.

## Critères validés

| Nº | Critère | Preuve attendue | État |
| --- | --- | --- | --- |
| 1 | Chaque tuile de catégorie utilise des albums dont le genre primaire ou secondaire correspond | Contrôle des 25 catégories disponibles, rejet des genres inconnus | PASS |
| 2 | Livres audio ne renvoie plus la liste d'artistes populaires | Livres audio, Jazz et Rock distincts en ligne | PASS |
| 3 | Les livres audio ouvrent les chapitres de l'album choisi | Chargement d'une liste de chapitres et type `audiobook` | PASS |
| 4 | Les résultats génériques ou indisponibles ne remplissent pas une catégorie | Tests avec métadonnées incorrectes, manquantes et erreur réseau | PASS |
| 5 | Une recommandation de playlist correspond au terme recherché | Correspondance de mots entiers, accents et alias de genres | PASS |
| 6 | Le contenu d'une recommandation confirme sa relation au thème ou à l'artiste | Validation d'un échantillon de pistes ; rejet de Renaud Capuçon pour Renaud | PASS |
| 7 | Les classements France proviennent d'une source officielle sans compte | Flux JSON iTunes France et résolution exacte vers Deezer | PASS |
| 8 | Les classements et fiches respectent les artistes et versions identifiés | Noms complets, variantes demandées, homonymes, relation titre → artiste → album et ambiguïtés omises | PASS |
| 9 | Ordre, doublons, erreurs de quota et requêtes répétées restent maîtrisés | Tests d'ordre, déduplication, cache et classification des erreurs | PASS |
| 10 | Trois passes donnent des résultats reproductibles sans élargir les critères pour remplir l'écran | Trois suites finales de 133/133 tests, aucun échec ni test ignoré | PASS |

## Sources et limites

Le catalogue public Deezer fournit les genres, métadonnées et sélections. Le classement France utilise le [flux officiel iTunes France](https://itunes.apple.com/fr/rss/topsongs/limit=50/json). Il est présenté comme un classement des ventes iTunes. Le [flux Apple Music](https://rss.marketingtools.apple.com/api/v2/fr/music/most-played/50/songs.json), proposé par le [générateur RSS Apple](https://rss.marketingtools.apple.com/), a été étudié puis écarté après des délais d’attente reproductibles dans l’environnement testé.

Autre option vérifiée dans sa [documentation officielle](https://musicbrainz.org/doc/MusicBrainz_API) : MusicBrainz fournit des métadonnées en JSON, sans clé API pour les lectures publiques. Le service est gratuit pour un usage non commercial et impose au maximum une requête par seconde avec un User-Agent explicite. Il pourrait enrichir les fiches artistes et albums ; il n’est pas intégré à cette version, dont le besoin immédiat est un classement d’accueil et des catégories fiables.

Seuls les noms et artistes du flux retenu servent à retrouver un résultat Deezer correspondant ; aucun prix, image, extrait ou fichier audio Apple n’est utilisé. Le parseur exige des entrées Music/Track, des identifiants numériques, des noms non vides et un lien artiste Apple officiel. Si la récupération ou la résolution est insuffisante, le classement Deezer est affiché avec son attribution distincte.

Les métadonnées de genre restent celles du catalogue. Un album peut légitimement relever de plusieurs genres (un livre audio pour enfants peut être classé Jeunesse et Livres audio). Les playlists tierces restent évolutives : l’audit vérifie leur titre et un échantillon de contenu (majorité de 60 %), sans promettre que chaque piste du service tiers soit parfaitement classée. Une sélection non vérifiable est omise. Le nom complet de l’artiste est comparé pour distinguer, par exemple, Renaud de Renaud Capuçon.

Dans l’échantillon final de trois albums par catégorie, 74 albums sont validés sur les 25 catégories publiques : 24 catégories ont trois albums vérifiés, Jeunesse en possède deux. Le résultat Jeunesse dont la fiche ne confirme pas le genre 95 est omis. Lors de l’audit initial, seuls 72 albums étaient vérifiables ; le catalogue public a évolué entre les essais. L’application ne remplace pas les résultats manquants par une liste généraliste.

Les sélections d’accueil ne couvrent pas systématiquement chaque thème : les passes finales trouvent des playlists vérifiées pour Pop, Rap, Rock, Electro et Jazz, mais omettent Chanson française, Soul et Latino lorsqu’aucun résultat de l’échantillon ne satisfait les critères. La popularité d’un homonyme facilite son classement dans une recherche générale ; elle ne prouve jamais l’identité de l’artiste d’un morceau. Une fiche sans lien d’identité fiable reste partielle. La disponibilité du streaming, les quotas, les contenus publics et les délais peuvent changer après l’audit.

## Preuves reproductibles

- `swift test --filter CatalogCoherenceTests` : tests isolés des genres secondaires, de rejet, d’ordre, de recommandations, des noms d’artistes, du parseur iTunes, du repli et du cache.
- `EASYMUSIC_NETWORK_TESTS=1 swift test --filter CatalogCoherence` : 16 tests, dont quatre contrôles réseau couvrant les 25 catégories, les chapitres de livres audio, les recommandations et la résolution du classement français.
- `EASYMUSIC_NETWORK_TESTS=1 swift test --filter OfficialFeedStabilityTests` : flux officiel iTunes, 50 entrées après le parcours des 25 catégories ; réussi en 18,07 s.

Les essais initiaux ont échoué et déclenché des corrections (quota, rapprochement de noms, source Apple instable). Ils ne sont pas comptés comme des validations. Les journaux locaux de la version corrigée sont `.tools/coherence-itunes-pass1.log`, `.tools/coherence-itunes-pass2.log` et `.tools/coherence-itunes-pass3.log`.

### Trois passes ciblées du catalogue avant validation finale

| Passe | Tests | Échecs | Durée |
| --- | ---: | ---: | ---: |
| 1 | 16 | 0 | 49,70 s |
| 2 | 16 | 0 | 47,65 s |
| 3 | 16 | 0 | 47,56 s |

Les trois passes confirment les mêmes livres audio, les mêmes sélections Jazz/Rock, les mêmes recommandations Renaud et le même classement iTunes résolu. Aucun contenu générique n’a été ajouté pour augmenter le nombre de résultats.


## Lecture distante ajoutée en 0.5.0

Le catalogue et ses critères de sélection restent ceux validés lors des trois passes ci-dessus. La lecture distante ajoute un contrôle distinct : le résultat doit correspondre au titre, à l’artiste et à la durée, être audio seul et être lisible par AVFoundation. Une réponse contenant un DRM, un aperçu, une piste vidéo, un format incompatible ou une durée éloignée est écartée. Une défaillance déclenche l’essai d’une autre source respectant les mêmes critères.

Le résolveur utilise `yt-dlp --skip-download --dump-single-json`, ne définit aucun fichier de sortie et garde les résultats en mémoire. Aucun extrait Apple n’est utilisé. L’URL audio signée est remise directement à AVPlayer. Le User-Agent de l’extracteur peut être transmis avec l’option publique [AVURLAssetHTTPUserAgentKey](https://developer.apple.com/documentation/avfoundation/avurlassethttpuseragentkey) ; les valeurs avec retours à la ligne sont rejetées. Les processus sont arrêtés à l’annulation et la résolution possède une échéance de 55 secondes.

La passe `.tools/streaming-pass3-soundcloud.log` valide **12 tests sur 12** en 27,87 secondes : neuf tests isolés et trois essais réels. L’essai d’annulation arrête rapidement une résolution active. « La ballade nord-irlandaise » de Renaud se résout vers un flux SoundCloud complet de 208,56 secondes, avec une piste audio et aucune piste vidéo, sans ajout aux dossiers audio surveillés. Le démarrage est préparé en 7,11 secondes, contre 20 à 22 secondes avec l’ordre précédent des sources. Une piste de test Blender est effectivement lue par AVPlayer puis poursuit sa lecture après un déplacement à 45 secondes, au-delà d’un extrait.

Pour les titres de catalogue, SoundCloud est interrogé avant YouTube avec les mêmes seuils de correspondance. Les liens directs gardent la priorité à leur source. Un échec n’assouplit ni la correspondance ni les exigences de format. Le délai de préparation reste variable selon les services ; les résultats observés ne constituent pas une promesse de délai maximal de démarrage.

La seconde mesure indépendante Renaud confirme le même flux intégral en **7,45 secondes**, sans ajout de fichier audio (`.tools/streaming-renaud-speed-pass2.log`, 1/1 test réussi). Les trois passes globales de la version finale sont consignées par l’audit qualité général.

## Recherche et homonymes : correction issue du contrôle visuel

Le contrôle de l’application a identifié deux erreurs supplémentaires : une recherche titre + artiste pouvait placer une reprise devant le titre original, et la recherche publique Deezer plaçait un homonyme peu suivi de Renaud avant le chanteur attendu. Le classement combine désormais les termes du titre et de l’artiste, respecte les noms complets et conserve les variantes explicitement demandées. Les égalités gardent l’ordre du fournisseur. Pour des artistes au nom strictement identique, le nombre public `nb_fan` départage les résultats lorsque cette donnée est disponible pour tout le groupe ; aucune popularité n’est déduite d’une donnée absente.

La fiche d’un morceau possède un contrôle plus strict : elle utilise la relation artiste de `/track/{id}`, puis l’album du morceau lui-même. Pour un ancien titre sans identifiant Deezer, elle exige le même titre, le même artiste et un seul identifiant artiste parmi les résultats correspondants. Une relation ambiguë est masquée ; la popularité ne sert jamais à attribuer un titre à un artiste.

La passe `.tools/search-relations-pass1.log` valide **20/20 tests**, dont deux contrôles réseau. La recherche « La ballade nord-irlandaise Renaud » place Renaud devant la reprise de Perrot Olivier. Le classement des homonymes présente l’artiste **21** en premier. Le volet relie la piste **deezer:4622233** à cet artiste et à **Molly Malone : Balade irlandaise (Version Deluxe)** ; un chargement indépendant de l’album confirme la présence de cette piste précise. Les tests couvrent également Renaud Capuçon, les variantes live/remix/radio, les données de popularité absentes, les homonymes ambigus et l’annulation.
