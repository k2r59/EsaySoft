# Contrôle de cohérence — EasyMusic 0.6.0

Audit du 29 octobre 2026. Ce document couvre la cohérence du catalogue, des rapprochements de morceaux et des informations DJ. La signature, la notarisation et la publication du paquet relèvent du contrôle de distribution.

**Verdict final : 10/10 sur la matrice de cohérence définie ci-dessous.** La quatrième suite complète confirme le dernier état des sources : **167 tests réussis, aucun échec XCTest ni test ignoré**. Les quatre passes représentent 665 exécutions de tests ; la dernière comprend le nouveau contrôle des éditions 7 et 12 pouces. Cette note ne prétend pas mesurer une précision musicale de 100 %.

## Matrice de contrôle

| Nº | Critère | Preuves | État |
| --- | --- | --- | --- |
| 1 | Les catégories utilisent les genres réellement déclarés dans les albums | 25 catégories ; genres primaires et secondaires ; rejet des métadonnées absentes ou contradictoires | PASS |
| 2 | Livres audio, Jazz et Rock restent distincts et ouvrent le contenu choisi | Essais réseau sur les albums et chapitres, sans remplacement par les artistes populaires | PASS |
| 3 | Les sélections d’accueil correspondent à leur thème | Titre de playlist vérifié, puis majorité de 60 % d’un échantillon d’albums correspondant au genre | PASS |
| 4 | La personnalisation reste liée aux recherches et écoutes | Termes normalisés, poids plafonnés et décroissants ; contenu des recommandations Renaud vérifié | PASS |
| 5 | Le classement d’accueil possède une source identifiable sans compte | Flux officiel iTunes France, rapprochement titre/artiste et attribution ; repli Deezer distinct | PASS |
| 6 | Recherche et fiches ne choisissent pas arbitrairement un homonyme | Renaud devant sa reprise ; artiste 21 ; album contenant précisément la piste choisie ; ambiguïtés omises | PASS |
| 7 | La sélection audio respecte les indices de version et les contraintes du lecteur | Réutilisation locale stricte ; crédits artistes ; remix/live symétriques ; conflit 7/12 pouces rejeté ; audio seul, durée et absence de DRM contrôlés | PASS |
| 8 | Un BPM affiché possède une provenance et une valeur exploitable | Deezer réel, tags locaux, rejet de 0/NaN/infinis/booléens, estimation rythmique synthétique | PASS |
| 9 | Une tonalité affiche une note et une notation Camelot cohérentes, ou reste inconnue | 24 conversions et enharmonies ; silence/note isolée rejetés ; progression Do majeur 8B analysée par la chaîne réelle ; cache invalidé | PASS |
| 10 | Le dernier état du code passe une régression complète | Trois suites initiales 166/166 ; quatrième suite 167/167 après protection 7/12 pouces | PASS |

## Passes automatisées

Les résultats ont été recomptés à partir des lignes individuelles XCTest, avec vérification de l’unicité des tests. Les horaires sont ceux inscrits dans les journaux.

| Passe du 29 octobre 2026 | Début | Fin | Réussites | Échecs / ignorés | Durée |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | 14:00:41,638 | 14:03:17,561 | 166/166 | 0 / 0 | 155,923 s |
| 2 | 14:07:22,433 | 14:10:03,131 | 166/166 | 0 / 0 | 160,698 s |
| 3 | 14:10:18,062 | 14:12:57,838 | 166/166 | 0 / 0 | 159,776 s |
| 4, après dernier correctif | 14:13:23,289 | 14:15:54,379 | 167/167 | 0 / 0 | 151,090 s |

Journaux : `.tools/qa-0.6.0-final-pass1.log`, `.tools/qa-0.6.0-final-pass2.log`, `.tools/qa-0.6.0-final-pass3.log`, `.tools/qa-0.6.0-final-pass4.log`. Les trois premières passes précèdent la garde explicite 7/12 pouces ; elles ne sont pas présentées comme trois exécutions du code après cette garde. La relecture indépendante confirme que la quatrième reprend les 166 cas antérieurs et ajoute uniquement le test de contradiction 7/12 pouces, sans suppression de test.

## Catalogue et rapprochements

Chaque passe achevée contrôle 25 catégories et 74 albums de l’échantillon : trois albums pour 24 catégories, deux pour Jeunesse. Le résultat dont le genre n’est pas confirmé est omis. Les livres audio renvoient notamment des histoires de P’tit Loup et Anatole ; Jazz et Rock donnent des albums distincts de ces livres.

L’accueil trouve des playlists vérifiées pour Pop, Rap, Rock, Electro et Jazz. Chanson française, Soul et Latino peuvent être omis lorsqu’aucun résultat examiné ne satisfait les critères. Ces contrôles portent sur un échantillon : ils ne garantissent pas que chaque piste d’une playlist tierce corresponde parfaitement au thème.

La recherche « La ballade nord-irlandaise Renaud » place le chanteur attendu avant une reprise. Entre artistes de même nom, le nombre public de fans départage les résultats seulement lorsqu’il est fourni pour tout le groupe. Cette popularité ne sert jamais à attribuer un morceau à un artiste. La fiche suit la relation du titre Deezer ; l’essai réel confirme piste `deezer:4622233` → artiste `21` → album **Molly Malone : Balade irlandaise (Version Deluxe)**, avec la piste présente dans cet album.

La copie locale est réutilisée entre fournisseurs lorsque titre et artiste normalisés correspondent et que les durées diffèrent au maximum de 2 secondes. Parenthèses, tirets et notations 7"/7''/7inch sont harmonisés sans supprimer les mots de version. Pour une source distante, les marqueurs remix/live/cover doivent correspondre dans les deux sens ; un crédit artiste explicite incompatible est rejeté. Le dernier correctif refuse la contradiction explicite 7 pouces/12 pouces. Une taille non renseignée n’est pas assimilée à une contradiction.

Les essais réels couvrent Soushkin, Belgium Rave, Ma Benz et Renaud. Le flux Renaud est validé comme audio complet. Les trois autres titres de régression sont effectivement lus, avec contrôle de durée, absence de piste vidéo et poursuite après déplacement à 45 secondes. Sur les trois premières passes, leur relance prend environ 0,36 à 0,41 seconde grâce au cache ; le premier démarrage prend environ 5,1 à 11,2 secondes selon le titre et le service. Ce sont des observations, pas des garanties de latence.

## Sources et informations DJ

Le classement France provient du [flux officiel iTunes](https://itunes.apple.com/fr/rss/topsongs/limit=50/json), affiché comme **Top ventes France · iTunes**. Les ventes ne sont pas présentées comme des écoutes Apple Music. Seuls les noms et artistes servent au rapprochement avec Deezer ; aucun extrait Apple n’est utilisé.

L’endpoint public [Deezer Soushkin](https://api.deezer.com/track/118313368) renvoie 156,01 BPM sans authentification. L’intégration réseau confirme cette valeur et sa provenance, avec tonalité inconnue tant qu’aucune analyse n’est demandée. Les autres sondes effectuées pendant le développement ont donné 113,6 pour [Renaud](https://api.deezer.com/track/4622233), 171,6 pour [Lose Yourself](https://api.deezer.com/track/1109731) et 0 pour [Harder, Better, Faster, Stronger](https://api.deezer.com/track/3135556). Zéro signifie inconnu et n’est jamais affiché comme un tempo.

Les tags du fichier sont lus avec FFprobe : `TBPM`/`BPM` et `TKEY`/`initial_key`/`key`. La [spécification ID3](https://id3.org/id3v2.4.0-frames) définit le BPM et la tonalité initiale ; un tag peut donc décrire le début d’un morceau qui module ensuite. Les notes et modes sont convertis selon la [table Camelot officielle](https://mixedinkey.com/camelot-wheel/) : La mineur = 8A, Do majeur = 8B. Les 24 conversions, leurs noms français et les enharmonies sont testés.

En l’absence d’information, l’analyse locale décode trois passages de 20 secondes au maximum avec le FFmpeg embarqué, vers PCM16/WAV en mémoire. Le calcul spectral utilise [Accelerate/vDSP](https://developer.apple.com/documentation/accelerate/vdsp). La tonalité exige au moins deux passages concordants et aucune autre estimation confiante contradictoire. Le BPM estimé exige des attaques régulières et une périodicité confirmée ; aucune division ou multiplication arbitraire par deux ne force le résultat dans une plage DJ.

L’intégration réelle utilise un fichier WAV synthétique de 24 secondes, hors bibliothèque utilisateur : FFprobe → FFmpeg → DSP donne **Do majeur, 8B**, avec provenance **Estimation · audio**. Le fichier initial reste intact et aucun fichier d’analyse n’est créé à côté. Le remplacement par du silence, à taille égale et avec une date de modification décalée de 0,1 seconde, invalide correctement le cache et supprime l’ancienne tonalité. Les trois premières passes réalisent ce contrôle en 0,99 s, 1,14 s et 0,98 s ; la passe finale le confirme en 1,03 s.

Une fiche distante récupère seulement les métadonnées lors de son ouverture. Le bouton **Analyser l’audio** autorise l’analyse d’un extrait disponible, ou d’un flux résolu à défaut. Les résultats issus d’un extrait sont identifiés **Estimation · extrait**. Dans l’interface, les estimations portent `≈` et les données absentes restent `—`.

## Vérification indépendante de l’extrait Soushkin

Le contrôle visuel a constaté 156 BPM et une tonalité `—` après analyse de l’extrait. Pour distinguer une abstention de l’analyse d’un problème de décodage, le même extrait public a été décodé avec le FFmpeg embarqué et les mêmes paramètres, sans sauvegarde de musique ni fichier intermédiaire.

| Début de fenêtre | Durée PCM obtenue | RMS normalisée | Temps FFmpeg | Résultat |
| --- | ---: | ---: | ---: | --- |
| 0 s | 10,000 s | 0,097194 | 0,269 s | PCM16, mono, 22 050 Hz ; exit 0 ; stderr vide |
| 10 s | 10,000 s | 0,125528 | 0,242 s | PCM16, mono, 22 050 Hz ; exit 0 ; stderr vide |
| 20 s | 9,989 s | 0,147715 | 0,244 s | PCM16, mono, 22 050 Hz ; exit 0 ; stderr vide |

Ces mesures confirment un signal non silencieux et un décodage utilisable. Elles ne déterminent pas à elles seules sa tonalité. L’affichage `—` reste donc cohérent avec une confiance insuffisante ; aucun nombre Camelot ne doit être fabriqué pour remplir la fiche.

## Portée et limites du verdict

- La note porte sur les règles, états inconnus, conversions et parcours testés. Elle ne mesure pas un taux d’exactitude musical sur un corpus professionnel de morceaux annotés.
- Les BPM de catalogue et tags locaux sont des informations déclarées, sans confiance statistique fournie. Ils peuvent être erronés ou correspondre à une autre convention de tempo.
- La tonalité estimée décrit une tendance sur les passages examinés, pas nécessairement chaque section. Musique modulante, atonale, parlée, accordage atypique et extraits courts peuvent rester inconnus. Les nuances modales autres que majeur/mineur ne sont pas identifiées.
- La correspondance distante repose sur les métadonnées et la durée, sans empreinte audio. Les crédits ou versions absents ne permettent pas une identification absolue.
- Les services publics, leurs classements et les playlists évoluent. Les erreurs réseau, quotas ou données ambiguës donnent un résultat partiel ou inconnu ; ils ne justifient pas un remplacement arbitraire.
- Le cache DJ est en mémoire. Il est invalidé par identité, chemin, taille, date précise de modification et version d’analyse ; il n’est pas conservé après fermeture de l’application.

L’analyse native évite une dépendance payante. [libkeyfinder](https://github.com/mixxxdj/libkeyfinder) et [Essentia](https://essentia.upf.edu/licensing_information.html) ont été étudiés mais ne sont pas intégrés. AcousticBrainz n’est pas utilisé comme référentiel principal : son équipe a [arrêté la collecte en exprimant des réserves sur la qualité des données](https://musicbrainz.wordpress.com/2022/02/16/acousticbrainz-making-a-hard-decision-to-end-the-project/).
