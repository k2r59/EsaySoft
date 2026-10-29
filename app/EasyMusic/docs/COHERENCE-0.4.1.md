# Contrôle de cohérence — EasyMusic 0.4.1

Audit du 29 octobre 2026. Les dix critères ci-dessous sont validés : **10/10 sur la grille de cohérence définie**. Ce résultat décrit les contrôles exécutés, pas une garantie sur tous les contenus futurs des services tiers.

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
| 8 | Les rapprochements de classements ne confondent pas les artistes ou les versions | Noms d'artistes entiers, collaborations explicites, rejet des variantes live | PASS |
| 9 | Ordre, doublons, erreurs de quota et requêtes répétées restent maîtrisés | Tests d'ordre, déduplication, cache et classification des erreurs | PASS |
| 10 | Trois passes donnent des résultats reproductibles sans élargir les critères pour remplir l'écran | Journaux de régression, validation et contrôle final | PASS |

## Sources et limites

Le catalogue public Deezer fournit les genres, métadonnées et sélections. Le classement France utilise le [flux officiel iTunes France](https://itunes.apple.com/fr/rss/topsongs/limit=50/json). Il est présenté comme un classement des ventes iTunes. Le [flux Apple Music](https://rss.marketingtools.apple.com/api/v2/fr/music/most-played/50/songs.json), proposé par le [générateur RSS Apple](https://rss.marketingtools.apple.com/), a été étudié puis écarté après des délais d’attente reproductibles dans l’environnement testé.

Seuls les noms et artistes du flux retenu servent à retrouver un résultat Deezer correspondant ; aucun prix, image, extrait ou fichier audio Apple n’est utilisé. Le parseur exige des entrées Music/Track, des identifiants numériques, des noms non vides et un lien artiste Apple officiel. Si la récupération ou la résolution est insuffisante, le classement Deezer est affiché avec son attribution distincte.

Les métadonnées de genre restent celles du catalogue. Un album peut légitimement relever de plusieurs genres (un livre audio pour enfants peut être classé Jeunesse et Livres audio). Les playlists tierces restent évolutives : l’audit vérifie leur titre et un échantillon de contenu (majorité de 60 %), sans promettre que chaque piste du service tiers soit parfaitement classée. Une sélection non vérifiable est omise. Le nom complet de l’artiste est comparé pour distinguer, par exemple, Renaud de Renaud Capuçon.

Dans l’échantillon de trois albums par catégorie, 72 albums sont validés sur les 25 catégories publiques. Les trois premiers résultats Jeunesse n’exposent pas le genre 95 dans leur fiche : ils sont omis. L’application ne remplace pas ces résultats manquants par une liste généraliste.

## Preuves reproductibles

- `swift test --filter CatalogCoherenceTests` : tests isolés des genres secondaires, de rejet, d’ordre, de recommandations, des noms d’artistes, du parseur iTunes, du repli et du cache.
- `EASYMUSIC_NETWORK_TESTS=1 swift test --filter CatalogCoherence` : 16 tests, dont quatre contrôles réseau couvrant les 25 catégories, les chapitres de livres audio, les recommandations et la résolution du classement français.
- `EASYMUSIC_NETWORK_TESTS=1 swift test --filter OfficialFeedStabilityTests` : flux officiel iTunes, 50 entrées après le parcours des 25 catégories ; réussi en 18,07 s.

Les essais initiaux ont échoué et déclenché des corrections (quota, rapprochement de noms, source Apple instable). Ils ne sont pas comptés comme des validations. Les journaux locaux de la version corrigée sont `.tools/coherence-itunes-pass1.log`, `.tools/coherence-itunes-pass2.log` et `.tools/coherence-itunes-pass3.log`.

### Résultat des trois passes complètes après correction

| Passe | Tests | Échecs | Durée |
| --- | ---: | ---: | ---: |
| 1 | 16 | 0 | 49,70 s |
| 2 | 16 | 0 | 47,65 s |
| 3 | 16 | 0 | 47,56 s |

Les trois passes confirment les mêmes livres audio, les mêmes sélections Jazz/Rock, les mêmes recommandations Renaud et le même classement iTunes résolu. Aucun contenu générique n’a été ajouté pour augmenter le nombre de résultats.
