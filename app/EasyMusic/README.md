# EasyMusic

Première ébauche d’une application macOS native en SwiftUI. Recherchez un morceau, écoutez-le en streaming ou téléchargez son audio, puis organisez vos titres dans des playlists. L’interface reprend les repères de Spotify, avec une identité EasyMusic.

## Lancer l’application

Ouvrez `/Applications/EasyMusic.app` pour la version complète, ou utilisez son installateur DMG.

Pour reconstruire l’application, installez Xcode ou ses outils de développement, puis exécutez depuis ce dossier :

```sh
./scripts/build-app.sh
open dist/EasyMusic.app
```

Le script récupère yt-dlp 2026.10.26 depuis sa publication officielle et vérifie son SHA-256. L’application cible macOS 13 ou version ultérieure et les Mac Intel et Apple Silicon. La signature locale permet les essais sur ce Mac ; la distribution sur d’autres Mac nécessite une signature Developer ID et une notarisation.

FFmpeg est facultatif pour télécharger le format original. Il active la conversion MP3/M4A, les métadonnées et pochettes intégrées lors de ces conversions, ainsi que la lecture locale des fichiers Opus/WebM. Node.js, s’il est installé, sert aux défis JavaScript de YouTube. Le moteur les recherche dans les emplacements Homebrew usuels. Le paquet de distribution 0.6.0 intègre ces deux dépendances. Le script de compilation rapide ne les inclut que si `BUNDLE_RUNTIME=1`.

## Utiliser EasyMusic

1. Choisissez **Tout**, **Styles**, **Titres**, **Albums** ou **Artistes**, puis lancez la recherche. Les liens sont reconnus automatiquement. Un album ouvre ses morceaux ; un style ouvre les artistes associés.
2. Cliquez sur la flèche de téléchargement du morceau. Le format audio choisi par yt-dlp est conservé par défaut.
3. Retrouvez le fichier dans **Tous les titres**.
4. Créez une playlist avec le bouton **+**, puis ajoutez les titres avec leur menu **•••**. Cochez plusieurs playlists pour conserver le même titre dans chacune.

Le bouton Lire utilise le fichier local lorsqu’il existe, sinon un flux audio complet compatible avec macOS. Aucun fichier musical ni entrée de bibliothèque n’est créé par cette lecture en ligne. Le bouton Extrait reste limité à 30 secondes. Pour YouTube et SoundCloud, FFmpeg prépare un extrait de 30 secondes en cache. Sans FFmpeg, EasyMusic tente la lecture directe du flux, dont la compatibilité dépend du format. Une coche remplace le bouton de téléchargement quand le fichier existe déjà ; le bouton + ouvre un sélecteur de playlists. Si le fichier a été supprimé du disque, le téléchargement redevient disponible.

Cliquez sur un résultat pour consulter les qualités disponibles. Choisissez le format de sortie et le dossier de destination dans **Sources et réglages**. Une conversion ne peut pas améliorer la qualité du fichier source.

La recherche réunit les réponses disponibles sans attendre qu’une source défaillante réussisse. Pour un résultat Deezer, EasyMusic cherche une version sur YouTube et SoundCloud. La comparaison utilise le titre, l’artiste et la durée, et pénalise les reprises ou remixes non demandés. Une correspondance incertaine est refusée. En cas d’échec, une autre source audio est essayée automatiquement. Cette comparaison reste heuristique et ne garantit pas l’identité de deux enregistrements.

## Accueil

L’accueil présente les classements publics Deezer, des playlists de styles variés, les genres du catalogue et vos sélections récemment ouvertes. Ces données sont récupérées sans compte ni clé API, depuis les points d’accès publics `/chart/0/tracks`, `/search/playlist` et `/genre`. Les récents sont conservés localement. Les mix proposés proviennent du catalogue public et ne reproduisent pas les recommandations personnelles de Spotify.

## Sources

| Service | Fonction disponible sans clé API |
| --- | --- |
| YouTube, SoundCloud | Recherche et téléchargement via yt-dlp |
| Deezer | Recherche publique et extraits ; recherche de l’audio complet sur les autres sources |
| Spotify | Identification du titre depuis un lien public de morceau via oEmbed ; sélection parmi les résultats des autres sources |
| Bandcamp, Jamendo, Audiomack | Import d’un lien de morceau, selon les formats accessibles |
| Internet Archive, Vimeo, Mixcloud | Import d’un lien, selon les formats accessibles |

Les liens doivent utiliser HTTPS. Les albums du catalogue Deezer peuvent être ouverts puis téléchargés morceau par morceau depuis les actions de chaque morceau. Les liens Deezer de titre, album ou artiste sont reconnus. Les playlists publiques proposées sur l’accueil peuvent être ouvertes et leurs titres placés dans la file. Les liens de playlist Spotify, Deezer et YouTube Music ouvrent désormais l’import dédié. Les restrictions géographiques, les demandes de connexion et les changements des services peuvent empêcher certains téléchargements. EasyMusic ne déverrouille pas les contenus protégés.

## Exporter vers Offline Music sur iPhone

L’application visée est [Offline Music de Md Zakir Hossain](https://apps.apple.com/fr/app/offline-music/id1259949354).

1. Ouvrez une playlist ou **Tous les titres**.
2. Cliquez sur **Pour Offline Music**.
3. Choisissez un dossier local ou un dossier iCloud Drive.
4. Sur l’iPhone, ouvrez **Import → Files** dans Offline Music et sélectionnez les fichiers audio. Pour un transfert depuis le Mac, utilisez **Import → Computer** et suivez les instructions affichées sur l’iPhone.

L’export crée un dossier distinct, copie les fichiers compatibles et convertit les autres en MP3 si FFmpeg est disponible. Les fichiers originaux restent intacts. Les noms numérotés conservent l’ordre de la sélection. Un fichier M3U8 accompagne l’export pour les lecteurs compatibles.

La [documentation d’Offline Music](https://musicplayeroffline.com/faq/import) précise que le transfert depuis un ordinateur accepte les fichiers individuels, mais pas les dossiers ni les playlists. Aucune API publique de synchronisation n’a été identifiée. L’export EasyMusic ne synchronise donc pas les playlists avec Offline Music ; recréez-les sur l’iPhone. Le transfert sur un iPhone réel n’a pas été testé.

## Données et fichiers

- Musique par défaut : `~/Music/EasyMusic`.
- Bibliothèque et playlists : `~/Library/Application Support/EasyMusic/library.json`.
- Copies de lecture décodées : `~/Library/Caches/EasyMusic`.
- Dossier de destination : préférences locales de l’application.

Deux téléchargements peuvent avancer simultanément, avec quatre fragments parallèles par transfert. yt-dlp conserve son comportement de reprise des fichiers partiels et retente les requêtes une fois. La file en attente n’est pas conservée après fermeture de l’application. Les fichiers terminés et les playlists sont enregistrés. Les fichiers audio ne sont pas supprimés quand un titre est retiré d’une playlist.

## Vérifier le projet

```sh
swift test
EASYMUSIC_NETWORK_TESTS=1 swift test
swift build -c release
```

Les tests couvrent les formats audio accessibles, les correspondances, les domaines acceptés, les arguments du moteur, la conservation des playlists et les exports sans écrasement. Un téléchargement réel de l’audio de Big Buck Bunny, publié par Blender, a aussi été vérifié. Les recherches YouTube, SoundCloud et Deezer, les albums, artistes, styles, liens Deezer et métadonnées Spotify ont été vérifiés en ligne. Les extraits YouTube et SoundCloud ont été contrôlés avec AVFoundation : fichiers lisibles, durée inférieure à 31 secondes. Les autres sources restent dépendantes de leur disponibilité et des extracteurs yt-dlp.

Téléchargez uniquement les contenus que vous êtes autorisé à conserver.

## Références

- [yt-dlp : options et dépendances](https://github.com/yt-dlp/yt-dlp)
- [Spotify oEmbed](https://developer.spotify.com/documentation/embeds/reference/oembed)
- [Offline Music : import et transferts](https://musicplayeroffline.com/faq/import)

## Distribution et mises à jour

La version 0.5.0 dispose d’un lecteur à trois zones avec file de lecture, répétition, lecture aléatoire, volume et choix de sortie audio.

Le paquet universel embarque yt-dlp, Node.js, FFmpeg et FFprobe : aucune installation Homebrew n’est nécessaire chez le destinataire. La compilation des dépendances est reproductible avec `scripts/build-dependencies.sh`. Les sources FFmpeg/LAME et les licences sont jointes à l’archive source.

Pour fabriquer le DMG et le ZIP signés :

```sh
CODE_SIGN_IDENTITY='Developer ID Application: Les papas du code (WN9MHL56A9)' ./scripts/package.sh
```

Pour notariser, ajouter `NOTARY_PROFILE` avec le nom du profil enregistré dans le Trousseau. Le certificat de signature seul ne suffit pas. Le profil local utilisé pour la distribution est `EasyShoot` ; aucun identifiant secret n’est enregistré dans les sources.

Sparkle 2.10.0 utilise une clé EasyMusic distincte, stockée dans le Trousseau, et vérifie la signature du flux et du téléchargement. Les recherches automatiques sont facultatives ; une installation demande une action explicite et attend la fin d’une lecture, d’un téléchargement ou d’un export.

Le flux prévu est `https://k2r59.github.io/EsaySoft/easymusic/appcast.xml`. Il est alimenté par les releases EasyMusic du dépôt EsaySoft. Après notarisation, `python3 scripts/publish-update.py --notes CHEMIN_NOTES` prépare et vérifie le flux signé. `--publish` publie la release et le flux ; cette option nécessite un dépôt propre, dont le commit existe sur GitHub. La publication ne modifie que le flux EasyMusic ; les flux des autres applications sont conservés.

## Accueil adaptatif

Au premier lancement, l’accueil propose les hits et huit styles variés : pop, rap, rock, chanson française, électro, jazz, soul et latino. La section « Pour vous » apparaît selon les recherches réussies et les écoutes d’au moins dix secondes. Les écoutes pèsent davantage que les recherches, les répétitions rapprochées sont limitées et le poids des préférences diminue de moitié tous les trente jours.

Les 64 centres d’intérêt les plus pertinents sont conservés dans la bibliothèque locale. Aucun compte supplémentaire n’est nécessaire. Les trois principaux termes servent à rechercher des playlists dans le catalogue Deezer au retour à l’accueil ; le profil complet n’est pas envoyé. Les hits et les découvertes généralistes restent accessibles. « Réinitialiser les suggestions » dans les réglages efface ces préférences sans supprimer les fichiers ni les playlists.

## Importer une playlist

Cliquez sur **Importer une playlist** dans la barre latérale, puis collez un lien complet Spotify, Deezer ou YouTube Music. Un lien de playlist collé dans la recherche déclenche également l’import. L’application crée une playlist locale contenant la liste des titres, sans télécharger automatiquement les fichiers audio.

- Deezer : lecture du catalogue public avec pagination.
- YouTube Music : extraction des métadonnées par yt-dlp ; maximum 2 000 entrées par import. Les radios automatiques et listes nécessitant une connexion ne sont pas prises en charge.
- Spotify : lecture des métadonnées de la page publique intégrée, sans compte ni clé API. Cette page peut être indisponible ou limiter la liste affichée. Un avertissement permanent précise que l’exhaustivité n’est pas garantie, même pour une playlist publique. Aucun flux audio Spotify n’est téléchargé : les morceaux sont recherchés sur les sources audio accessibles.

**Télécharger les titres manquants** remplit la file de téléchargement. Les fichiers déjà reconnus sont réutilisés, les doublons de liens sont retirés et l’ordre des titres importés est conservé. Les échecs restent visibles pendant la session et peuvent être réessayés. Les listes importées persistent après redémarrage, mais la file de téléchargement n’est pas relancée automatiquement. Un nouvel import du même lien actualise la playlist existante. Les liens courts doivent être remplacés par leur lien complet.


## Playlists et détails (0.5.0)

Le bouton + ouvre un sélecteur avec recherche, création et sélection multiple. Ajouter un morceau distant conserve sa référence sans le télécharger ; il peut être écouté en streaming dans la playlist. La flèche de téléchargement permet de le rendre disponible hors connexion. Retirer un morceau d’une playlist ne supprime pas le fichier.

Le menu de la playlist permet de la renommer et de choisir sa pochette. Par défaut, elle reprend celle du premier titre. Le lien d’origine reste enregistré. Pendant l’utilisation, les listes importées sont vérifiées au plus toutes les quinze minutes ; une pastille signale les changements. Le bouton de synchronisation actualise les titres exposés par la source tout en conservant le nom local et la pochette.

Cliquez sur un titre pour ouvrir ses détails à droite. Les albums sont affichés lorsque l’artiste est identifié exactement dans le catalogue public. Aucun nombre d’auditeurs ni biographie ne sont inventés. Le débit local est mesuré avec ffprobe ; il est approximatif pour les fichiers à débit variable.

Dans une playlist, cliquez sur son titre ou le crayon pour la renommer. Le bouton corbeille de la barre d’actions supprime uniquement la playlist d’EasyMusic après confirmation : les fichiers audio et la liste sur le service d’origine restent conservés.

### Cohérence de l’accueil et lecture (0.5.0)

Les catégories ouvrent des albums dont le genre primaire ou secondaire correspond au choix, au lieu d’une liste d’artistes parfois générique. Les livres audio ouvrent leurs chapitres. Les recommandations de playlists sont vérifiées sur le titre et un échantillon du contenu ; les propositions sans lien vérifiable sont écartées.

L’accueil peut utiliser le classement des ventes France du [flux public iTunes](https://itunes.apple.com/fr/rss/topsongs/limit=50/json) : seuls les titres retrouvés avec une identité cohérente dans Deezer sont affichés, avec attribution du classement. Si ce flux ne répond pas, l’interface indique le classement Deezer utilisé. Aucun compte payant ni clé API ne sont nécessaires à ces lectures publiques. Les réponses Deezer sont mises en cache et les requêtes cadencées.

Le bouton lecture d’un titre distant résout un flux audio complet, sans téléchargement dans la bibliothèque. Une seconde pression annule la connexion. Choisir un autre titre ou un extrait remplace la demande précédente. La file de lecture peut mélanger des titres locaux et distants. Si un flux échoue, une autre source correspondant au même enregistrement est essayée ; les contenus protégés ne sont pas déverrouillés. La première connexion peut prendre quelques secondes selon la source et le réseau.

Le classement des recherches combine les termes du titre et de l’artiste. Les homonymes de même nom sont départagés par les abonnés publics du catalogue lorsque cette donnée est disponible. Les fiches utilisent l’identifiant du morceau ou une correspondance titre/artiste non ambiguë pour afficher l’artiste et ses albums ; une relation incertaine est omise.

### Lecture et préférences (0.6.0)

Dans une liste, le bouton lecture se trouve à gauche de la pochette. La pochette et le titre ouvrent les détails. Le cœur ajoute le morceau à **Titres aimés** sans le télécharger. Les détails permettent de lui attribuer de une à cinq étoiles ; cliquer à nouveau sur la note sélectionnée l’efface. Favoris et notes sont indépendants et conservés dans la bibliothèque locale.

Le streaming privilégie les flux HLS audio compatibles avec le lecteur natif. La durée et les pistes sont vérifiées sur un lecteur prêt, avant lecture ; un format refusé peut être remplacé par un autre format de la même source. Les fournisseurs sont interrogés en parallèle et la première source vérifiée est retenue. Les adresses de flux sont gardées en mémoire pendant quinze minutes au maximum, sous réserve de leur expiration. Le prochain morceau de la file est préparé pendant la lecture. Une première connexion dépend encore des services externes et peut prendre plusieurs secondes.

Les détails DJ indiquent la provenance des données : catalogue public, métadonnées du fichier ou estimation audio. Le BPM absent ou nul n’est pas affiché comme zéro. La tonalité est présentée avec sa note et son mode ainsi que sa correspondance Camelot. Une analyse peut rester indéterminée, notamment sur un extrait court, une introduction, un morceau peu tonal ou un changement de tonalité. L’analyse d’un titre distant se déclenche explicitement et ne l’ajoute pas à la bibliothèque.
