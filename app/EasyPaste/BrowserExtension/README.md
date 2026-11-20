# EasyPaste · Web

Extension Chrome locale, en français, sous licence MIT. Elle complète EasyPaste sans compte EasyPaste ni serveur intermédiaire. Les copies passent par le presse-papiers du système et fonctionnent aussi sans l’app. Une connexion locale facultative permet de vérifier le lien avec EasyPaste et de lui confier les téléchargements vidéo et audio, sans lire son historique.

## Installer depuis EasyPaste

Dans la nouvelle version locale de l’app :

1. Ouvrir **Réglages → Intégrations → Extension navigateur**.
2. Choisir **Arc** ou **Google Chrome**.
3. Cliquer sur **Installer dans…**. EasyPaste prépare l’extension, affiche son dossier dans le Finder et ouvre la page Extensions du navigateur.
4. Activer **Mode développeur**, puis utiliser **Charger l’extension non empaquetée** pour sélectionner le dossier `Extension` affiché.
5. Épingler **EasyPaste · Web** dans le navigateur.

Le navigateur exige cette validation manuelle. L’app ne peut pas installer silencieusement une extension. Si elle est déjà chargée depuis ce dossier, cliquer sur **Recharger** après la préparation des nouveaux fichiers.

## Installer depuis le ZIP

1. Ouvrir `chrome://extensions` dans Chrome.
2. Activer **Mode développeur**.
3. Cliquer sur **Charger l’extension non empaquetée** et choisir ce dossier `BrowserExtension`, celui qui contient `manifest.json`.
4. Dans le menu Extensions de Chrome, épingler **EasyPaste · Web**.

Aucune publication sur le Chrome Web Store n’a été faite. Pour installer depuis un ZIP, le décompresser d’abord, puis sélectionner son dossier. Pour une mise à jour locale, remplacer les fichiers et utiliser **Actualiser** sur la fiche de l’extension. Aucun système de mise à jour automatique n’est configuré.

## Relier l’app Mac (facultatif)

1. Dans EasyPaste, ouvrir **Réglages → Intégrations → Extension navigateur** et préparer la connexion pour le navigateur utilisé.
2. Dans le popup de l’extension, ouvrir la roue **Réglages**, puis cliquer sur **Connecter** et accepter l’accès local demandé par le navigateur.
3. La réponse affiche la version d’EasyPaste et l’heure de la vérification. **Vérifier** relance cet échange à la demande ; aucune connexion permanente n’est maintenue.

**Déconnecter** retire uniquement l’autorisation facultative `nativeMessaging` de cette extension. Les fonctions de copie et les copies existantes restent disponibles. Une app absente, une connexion désactivée ou un navigateur non autorisé affiche une action à effectuer dans les réglages. Une vérification native attend au maximum cinq secondes. À chaque ouverture, une connexion déjà autorisée est vérifiée pour afficher son état réel dans le pied de fenêtre. Aucune autorisation supplémentaire n’est demandée automatiquement.

La version 0.2.0 fixe l’identité publique de l’extension à `nmkechbpakkenabambdbpnaahhdlgpej`. Les anciennes versions locales avaient un identifiant dépendant du dossier choisi : vérifier l’identifiant dans la fiche de l’extension lors de la migration et retirer l’ancienne entrée si elle reste présente. La clé publique du manifeste n’est ni un secret ni une clé de compte.

## Copier une page

Cliquer sur l’icône EasyPaste, puis **Copier la page → Copier avec la mise en forme**. Une sélection de texte existante est proposée en priorité. Sinon, l’extension récupère le premier article, la zone principale ou, à défaut, le corps de la page.

La copie contient simultanément du **HTML nettoyé** et du **texte brut** : titres, emphases, couleurs de texte et de fond, tailles raisonnables, listes, liens, blocs de code et tableaux. L’application dans laquelle on colle choisit le format qu’elle sait lire. La reproduction n’est pas une capture à l’identique de la mise en page : les grilles complexes, polices téléchargées, scripts et interactions sont retirés.

Le lien visible de la source peut être ajouté ou omis. Le HTML copié contient aussi une métadonnée discrète `easypaste-source-url`, issue de l’adresse de la page ouverte, pour qu’EasyPaste puisse proposer de revenir à l’origine. Elle n’ajoute aucun texte visible et ne modifie pas le texte brut. Seules les adresses HTTP(S) sans identifiant ni mot de passe sont retenues. Les images distantes ne sont pas chargées ou incorporées ; leur texte alternatif est conservé lorsqu’il existe. Les champs de saisie, éléments masqués, contenus intégrés, SVG, formulaires et lecteurs vidéo sont exclus. Les pages internes de Chrome, le Chrome Web Store, certains PDF et les cadres d’un autre domaine ne sont pas accessibles.

Si l’historique d’EasyPaste est activé, l’app récupère cette copie comme n’importe quelle copie habituelle. L’extension n’accorde aucune nouvelle autorisation à l’app macOS.

## Copier les sous-titres YouTube

Sur une vidéo, un Short ou une page de direct YouTube, l’action **Sous-titres** propose les langues disponibles. Le français manuel est préféré, puis le français automatique, puis la première piste disponible. Les pistes automatiques portent la mention **Automatiques**.

- Ouvrir **Sous-titres** charge directement un aperçu modifiable, sans changer le presse-papiers.
- **Copier les sous-titres** copie le texte affiché, y compris vos modifications.
- **Afficher les horodatages** ajoute les horodatages. Changer cette option régénère l’aperçu et efface les modifications manuelles.
- **Transcription YouTube** lit la langue du panneau natif. EasyPaste ouvre ce panneau au besoin, lit son modèle complet ou parcourt les lignes chargées au défilement.

L’aperçu reste disponible tant que la fenêtre de l’extension est ouverte. Changer de piste ou actualiser les pistes l’efface. Effacer toute recherche dans le panneau de transcription pour éviter de ne copier qu’un résultat filtré.

Le code fourni dans `youtube-sous-titres.zip` a été intégré à la récupération directe : contexte visiteur anonyme renouvelé, client lecteur VISIONOS, correspondance exacte entre langue et type de piste, réponse JSON3. Il sert aussi à lire le modèle du nouveau panneau de transcription. Les requêtes directes n’envoient aucun cookie de compte. Une piste indisponible ne déclenche pas de remplacement silencieux par une autre langue.

YouTube peut modifier son lecteur ou refuser une piste. L’extension ne transcrit pas elle-même l’audio et ne fabrique pas de traduction. Une récupération de sous-titres qui échoue laisse le presse-papiers intact.

## Télécharger une vidéo ou son audio

Cette fonction nécessite EasyPaste 0.3.14 ou ultérieur et sa connexion navigateur. Les versions 0.3.13 et antérieures ne comprennent pas ces commandes.

1. Ouvrir **Télécharger** dans l’extension.
2. Choisir **Vidéo · MP4** ou **Audio · MP3**. Ce choix ne lance aucun téléchargement.
3. Pour une vidéo, choisir la qualité, puis cliquer sur **Télécharger la vidéo** ou **Télécharger l’audio**. Pour un flux alternatif, utiliser **Réglages → Choisir un autre média**.
4. Autoriser la connexion locale si le navigateur la demande.
5. Le popup affiche **Préparation**, **Téléchargement en cours**, puis **Téléchargement terminé** uniquement après confirmation du moteur. Une animation indique le travail en cours sans inventer de pourcentage. Le suivi du dernier téléchargement reprend à la réouverture pendant 24 heures. La fenêtre **Téléchargements web** d’EasyPaste donne aussi accès aux fichiers. **Annuler** interrompt une tâche ; **Afficher** révèle le fichier terminé.

Le téléchargement continue après fermeture de l’extension. Le menu d’EasyPaste permet de rouvrir la fenêtre de suivi. Deux téléchargements peuvent s’exécuter simultanément ; les suivants attendent. Quitter EasyPaste annule les tâches en cours après confirmation.

Les fichiers sont enregistrés dans `~/Downloads/EasyPaste`, dans un dossier distinct par demande. Les fichiers existants ne sont pas remplacés. Le mode vidéo propose la meilleure qualité disponible ou un plafond de 1080p, 720p ou 480p, puis assemble ou remuxe en MP4. Les sources sans hauteur connue sont acceptées à leur résolution native. Le mode audio convertit en MP3. Le délai maximal d’une tâche de téléchargement est de 30 minutes ; yt-dlp reçoit une limite de 2 Go par téléchargement.

La détection couvre les éléments vidéo/audio, leurs sources et les médias déclarés dans la page. yt-dlp peut aussi analyser une page sans flux direct visible. Les sites pris en charge varient avec sa version. Les lecteurs dans des cadres inaccessibles, les sources exigeant des cookies, les DRM et les directs en cours ne sont pas pris en charge par ce parcours. Une page de liste doit être ouverte sur un média précis.

### Moteurs nécessaires sur le Mac

À partir de la version 0.3.15, EasyPaste embarque directement yt-dlp, FFmpeg, ffprobe et Node, signés avec l’application, pour Mac Intel et Apple Silicon. Aucun EasyMusic, Homebrew, Python ou outil séparé à installer : le téléchargement démarre depuis l’extension. Les moteurs sont mis à jour avec EasyPaste et seuls ceux de son paquet sont utilisés. La version publique 0.3.14 nécessite encore les composants externes ; cette intégration sera distribuée dans la prochaine mise à jour.

Le menu transmet l’URL choisie, le format et la qualité à l’app. L’app lance les exécutables avec des arguments séparés, ignore les configurations personnelles yt-dlp et ne lit pas les cookies du navigateur. Les fichiers temporaires d’une tâche annulée ou échouée sont supprimés dans son propre dossier.

## Confidentialité et sécurité

- **`activeTab`** : accès temporaire à l’onglet lorsque l’utilisateur ouvre l’extension.
- **`scripting`** : extraction déclenchée dans cet onglet, sans script installé sur tous les sites.
- **`clipboardWrite`** : copie explicite dans le presse-papiers. L’extension ne lit pas son contenu.
- **`nativeMessaging`**, facultative : une vérification ponctuelle de l’app Mac ou l’envoi explicite d’une demande de téléchargement. Elle est demandée au clic sur **Connecter**, **Vérifier** ou le bouton final de téléchargement. La refuser ne désactive aucune copie.

Pas de permission globale sur les sites, de lecture des cookies via l’API Chrome, de lecture de l’historique, de télémétrie ou de worker permanent. Les requêtes directes de sous-titres utilisent un contexte anonyme, sans cookies. Le popup charge uniquement la miniature de la vidéo YouTube depuis `i.ytimg.com`, sans référent, lorsqu’une vidéo est reconnue. Aucun contenu de page n’est envoyé à ce serveur de miniatures.

Le connecteur local `app.easypaste.web` reçoit `hello` (vérification), `media` (demande explicite) ou `mediaStatus` (suivi d’une demande par identifiant). Chaque réponse doit correspondre au nonce aléatoire. Le suivi n’expose ni chemins de fichiers ni historique. Le popup conserve localement l’identifiant, le format et la date du dernier téléchargement pendant 24 heures, sans titre ni URL. Il interroge le suivi toutes les 1,5 seconde tant qu’il est ouvert et qu’une tâche est active ; il ne maintient aucun port persistant ni serveur local. Fermer le popup n’interrompt pas le téléchargement déjà confié à l’app.

Le HTML est **reconstruit** avec une liste blanche de balises et de propriétés CSS. Les attributs d’événement, scripts, styles arbitraires, URL `javascript:`, ressources distantes, SVG, MathML, cadres et objets ne sont jamais recopiés. Aucun HTML de la page n’est injecté dans le popup. La CSP interdit les connexions et scripts distants dans le popup ; seule l’image de miniature depuis `i.ytimg.com` est autorisée en plus des ressources locales.

Les limites sont de 500 000 caractères, 2 Mo de HTML encodé en UTF-8, 8 000 nœuds, 2 000 éléments stylés et 60 niveaux d’imbrication. En cas de dépassement, l’utilisateur est invité à sélectionner un passage plus court : le presse-papiers n’est pas remplacé par un extrait tronqué. Le parcours laisse régulièrement la main au navigateur. Sous-titres : 2 Mo de réponse, 12 000 segments, 500 000 caractères, délai réseau de 15 secondes par requête directe (trois requêtes au maximum), lecture du panneau natif limitée à 12 secondes. Aucune surveillance des pages ni tâche automatique en arrière-plan ; une extraction déjà déclenchée peut terminer son parcours après la fermeture du popup.

## Version 0.3.0

Récupération YouTube adaptée du ZIP fourni, choix exact de langue, aperçu modifiable, lecture du modèle de transcription virtualisé et dédoublonnage des passages identiques au même instant. Menu de téléchargement vidéo/audio pour les sites compatibles et les flux détectés. Parcours d’installation guidé dans l’app Mac. Permissions obligatoires et identité de l’extension inchangées.

## Version 0.2.0

Connexion facultative à l’app Mac et identité publique stable. Les échanges sont limités à une vérification explicite ; la copie et sa mise en forme fonctionnent indépendamment. La carte indique le résultat et la dernière vérification effectuée dans le popup ouvert. Compatibilité native attendue : protocole 1, bridgeVersion 1.

## Version 0.1.2

Les copies de page, de sélection et de transcription conservent leur URL d’origine dans le HTML transmis au presse-papiers. Le texte brut et l’option d’attribution visible restent inchangés. L’adresse est vérifiée avant l’écriture pour ne pas associer une ancienne copie à une page différente.

La métadonnée est une balise HTML void `<meta name="easypaste-source-url" content="…">` placée dans `<head>`. Elle est produite par `createElement` et `setAttribute`, puis sérialisée par le DOM : un `&` est encodé `&amp;`, les guillemets d’attribut sont échappés, l’adresse est normalisée par `URL`. Le destinataire doit lire du HTML et décoder ses entités ; il ne faut pas traiter le document comme du XML strict. Les copies ordinaires faites hors extension ne sont pas modifiées par celle-ci.

## Version 0.1.1

Correction des pistes YouTube vides : lecture native prioritaire, ouverture automatique du panneau, compatibilité avec sa nouvelle structure, parcours des listes chargées à la demande et contrôle de la vidéo active. Permissions inchangées.

## Développement et tests

L’extension n’a **aucune dépendance à l’exécution** ni compilation nécessaire. Les PNG de l’icône sont des dessins originaux EasyPaste. `jsdom` sert uniquement aux tests.

```sh
npm ci --ignore-scripts
npm test
```

Pour garder les dépendances sur le disque interne de ce Mac :

```sh
npm install --prefix /Users/k2r59/Library/Caches/EasyPaste-extension-tests --no-audit --no-fund jsdom@26.1.0
NODE_PATH=/Users/k2r59/Library/Caches/EasyPaste-extension-tests/node_modules npm test
```

Les tests couvrent la sélection exacte, la mise en forme, les injections HTML/CSS/URL, les éléments masqués, les budgets, les rendus intermédiaires, les réponses YouTube XML/JSON3 malformées, les vidéos changées par navigation interne, les domaines usurpés, les refus/erreurs réseau et l’écriture simultanée HTML + texte. Ils ne remplacent pas une vérification réelle de Chrome et de YouTube ; voir [QA-0.3.0.md](QA-0.3.0.md).

## Références

- [Chrome : accès temporaire à l’onglet actif](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab).
- [Chrome : injection de scripts Manifest V3](https://developer.chrome.com/docs/extensions/reference/api/scripting).
- [Chrome : permissions du presse-papiers](https://developer.chrome.com/docs/extensions/reference/permissions-list).
- [YouTube : afficher une transcription](https://support.google.com/youtube/answer/15930243?hl=fr).
- [YouTube Data API : téléchargement de sous-titres](https://developers.google.com/youtube/data/reference/rest/v3/captions/download). Cette API exige le droit de modifier la vidéo et n’est pas utilisée par l’extension.

Le code est sous [licence MIT](LICENSE). Les droits sur le contenu copié restent ceux de son auteur.
