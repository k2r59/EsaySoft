# EasyPaste / EasySoft : reprise de développement sur un autre Mac

État de reprise préparé le **24 octobre 2026**. Ce document s’adresse à Hervé et à l’agent qui reprendra le projet. Il consigne les décisions de la conversation, l’état du code, les preuves de tests et le travail restant. Les chemins absolus de l’ancien Mac sont des repères de diagnostic ; ils doivent être adaptés sur le nouveau Mac.

## 1. Priorité au démarrage de la prochaine session

1. Lire ce document avant de modifier le projet.
2. Vérifier la branche, le dernier commit et `git status --short`. Le répertoire de départ de Codex peut appartenir à un autre projet.
3. Vérifier la présence des fichiers et des commits de sources décrits dans la section « État Git et transfert ». La branche de reprise contient désormais le MD et les sources de travail.
4. Consulter la section « Travail restant » avant de considérer la version locale comme terminée.
5. Consulter la dernière section de publication. **Le 26 octobre 2026, Hervé a autorisé la publication de la dernière version d’EasyPaste, levant la consigne précédente de rester en version privée pour cette livraison.**

La demande immédiate d’Hervé est de disposer de ce fichier sur Git pour continuer depuis son autre Mac, sans perdre le contexte. Le transfert du MD et une publication OTA sont deux opérations distinctes.

## 2. État Git et transfert

| Élément | Valeur vérifiée au début de cette reprise |
| --- | --- |
| Dépôt GitHub | `https://github.com/k2r59/EsaySoft.git` |
| Orthographe du dépôt | `EsaySoft`, malgré les noms des applications `EasyPaste`, `EasyShoot`, `EasyTile` |
| Répertoire de travail sur l’ancien Mac | `/Volumes/EXT/Dev/EsaySoft-quality` |
| Branche de départ | `codex/annotation-studio-preview` |
| Branche de reprise ciblée pour ce document | `codex/reprise-easypaste-2026-10-24` |
| HEAD avant l’enregistrement de ce document | `5c5b01c8980087193bb7c01ae691234b77cd187d` |
| Branche distante de départ | `origin/codex/annotation-studio-preview`, même commit vérifié |
| Dernière version publique EasyPaste vérifiée sur GitHub | `easypaste-v0.3.6`, publiée le 23 octobre 2026 à `08:57:15Z` |
| Version de l’application locale | `0.3.6`, build `23`, avec des modifications privées supplémentaires |
| Licence du projet | MIT, avec les attributions des dépendances à conserver |

Le numéro `0.3.6 (23)` ne suffit donc pas à identifier le code testé sur l’ancien Mac : la copie locale contient du travail postérieur à la version publique. Identifier aussi le commit ou l’archive de sources.

### État des sources au moment de la rédaction

Les modifications de travail couvrent `app/EasyPaste`, plusieurs fichiers d’annotation d’EasyShoot, `docs/annotation-studio` et deux utilitaires dans `scripts/`. Les fichiers nouveaux ont été ajoutés à Git avec les modifications des fichiers existants.

**Premier push du MD confirmé :** branche `codex/reprise-easypaste-2026-10-24`, commit `bcefccebdac48b23442dff6094f5d8eb6f78701b`, vérifié avec `git ls-remote`. Le MD reçoit ensuite des compléments de tests sur cette même branche.

**Hervé a validé « MD et sources sur une branche de travail ».** La branche `codex/reprise-easypaste-2026-10-24` regroupe le document et les deux points de sauvegarde suivants :

| Commit de sources | Contenu | Niveau de validation |
| --- | --- | --- |
| `54f7d35` | EasyPaste : interface en verre, palettes, icônes, dimensions, titres des tuiles, aperçu, extension et pont natif, ressources et tests | 285 tests Mac et 60 tests extension réussis pendant la session ; compilation universelle et paquet de préparation signé ; essais manuels restant à terminer ci-dessous |
| `38d5c1b` | EasyShoot : état de travail de l’annotation commune, tests associés, brief et utilitaires de développement | Sauvegarde de reprise ; parité des 7 fichiers partagés vérifiée, sans déclaration de validation complète d’EasyShoot pendant cette session |

Un clone à jour de cette branche contient donc les sources récentes et les fichiers nécessaires à leur reprise. Le transfert sur cette branche ne crée ni tag, ni GitHub Release, ni mise à jour d’appcast. `main` n’a pas été fusionnée ou remplacée. Les binaires, installateurs, caches de compilation, historiques utilisateur et secrets du trousseau restent hors de ces commits.

Avant de reprendre sur l’autre Mac, confirmer la présence de ces commits dans `git log` après `git fetch` et `git pull --ff-only`. Les fichiers de travail étaient propres après les deux commits de sources ; les derniers changements du MD les accompagnent dans un commit de documentation distinct.

Une archive complète des fichiers de travail a aussi été créée sur le SSD interne, `source-complete-reprise-2026-10-24.zip`, avant l’enregistrement des sources. Son chemin est indiqué dans les repères locaux. Elle sert de sauvegarde de secours ; le clone de la branche de reprise suffit désormais pour le code et le MD. Éviter de recopier par-dessus ce clone une ancienne version du MD contenue dans l’archive. Vérifier le fichier `.sha256` adjacent en cas de restauration. Cette archive est locale et n’est pas publiée sur GitHub.

Préserver les changements EasyShoot déjà présents. Ne pas les effacer, les réinitialiser ou les inclure aveuglément dans une livraison EasyPaste. Ils appartiennent notamment au chantier d’annotation commun.

Commandes de vérification :

```sh
git remote -v
git branch -vv
git status --short
git log -5 --oneline
git diff --check
```

### Reprendre le dépôt sur le nouveau Mac

```sh
git clone https://github.com/k2r59/EsaySoft.git
cd EsaySoft
git fetch origin
git switch codex/reprise-easypaste-2026-10-24
git pull --ff-only
```

Vérifier que le push de cette branche est confirmé avant de quitter l’ancien Mac. Lire le commit qui contient ce MD pour connaître le point exact à récupérer. Éviter de reprendre `main` par défaut : cette branche n’est pas le point de travail courant.

## 3. Décisions produit à conserver

### Langue et périmètre

- Application et libellés en français.
- EasyPaste est d’abord une application Mac locale.
- La distribution courante fonctionne sans iCloud.
- La synchronisation iCloud de **tout l’historique** a été souhaitée, mais sa configuration Apple a été bloquée par les droits de l’équipe. Ce chantier est distinct ; ne pas prétendre que le cloud est opérationnel.
- Conserver les trois applications dans le dépôt sous `app/` et maintenir la licence MIT et les notices tierces.

### Interactions validées pour les tuiles

- Toute la surface du bouton ou de l’onglet est cliquable, y compris les marges.
- Un clic simple sur une tuile sélectionne ; un double-clic colle.
- Les actions en bas de tuile sont : aperçu si disponible, page d’origine si disponible, favori, corbeille rouge.
- Un clic simple sur l’étoile ajoute ou retire le favori.
- La suppression utilise une confirmation avec l’option de ne plus demander ; conserver les mécanismes de corbeille et de restauration.
- L’aperçu remplace les anciens pieds de tuile trop chargés par le nombre de caractères.
- Les copies de texte doivent afficher le contenu **une seule fois** dans les tuiles. Masquer le titre généré lorsqu’il répète le début du contenu ; conserver un véritable titre personnalisé.
- À l’ouverture de l’historique, conserver la dernière sélection lorsqu’aucune nouvelle copie n’est arrivée. Après une nouvelle copie externe, sélectionner le nouvel élément le plus récent.

### Collage

- `⇧⌘V` doit ouvrir la barre rapide seule, sans faire remonter la bibliothèque derrière elle.
- Le collage doit retourner dans l’application d’origine ; un ancien navigateur ne doit pas voler la destination lorsqu’on souhaite coller dans Codex ou un autre éditeur.
- Le collage direct nécessite l’autorisation Accessibilité. Les captures nécessitent l’enregistrement de l’écran.
- Préserver le collage riche, le collage en texte brut et le collage de plusieurs éléments / pile.
- Le collage spécial « valeurs uniquement » de Google Sheets utilise parfois un presse-papiers interne au classeur. Ne pas promettre de contrôler ce comportement distant sur la seule base d’un test de presse-papiers local.

### Apparence validée

- Style Liquid Glass inspiré des maquettes approuvées, avec priorité à la lisibilité.
- Utiliser les API natives de verre disponibles à partir de macOS 26 ; conserver un repli sur macOS 15.
- Prévoir les thèmes et le pourcentage de transparence dans Apparence.
- Les boutons, la sélection et les onglets actifs suivent la palette du thème. Éviter le retour du vert fixe sur un thème bleu, rose ou violet.
- Préserver les réglages d’accessibilité : contraste renforcé, réduction de la transparence et réduction des animations.
- Barre rapide : marque **P seule**, sans le mot « EasyPaste » à côté. Logo ruban transparent, contrasté selon le thème. L’icône native de l’application reste distincte de cette marque d’interface.
- Utiliser les icônes réelles des applications sources lorsqu’elles sont identifiées ; leur chargement doit être mis en cache et réalisé hors du fil principal.
- Bibliothèque : fond continu avec dégradé ; éviter les panneaux superposés autour de la colonne de gauche, des filtres, du titre, du champ de recherche et du pied de page.
- Filtres de type : onglet actif identifiable, notamment par le soulignement. Préserver un état de focus visible.
- L’aperçu de la barre forme un **T inversé**, dans la même silhouette que la barre. Il se déploie vers le haut et garde le bas de la barre fixe.
- Les actions de l’aperçu sont de petites icônes : annoter/modifier, copier, coller, favori, corbeille rouge. Conserver les infobulles et les noms accessibles.
- Le reflet de séparation doit être **court, centré, avec les extrémités fondues**. Il ne traverse pas toute la largeur et ne touche pas les boutons.

Hervé est strict sur la ressemblance avec les maquettes. Une revue précédente a attribué 10/10 à des critères visuels convenus, pas à une identité pixel par pixel ni à l’absence de bugs. Une nouvelle revue ciblée a ensuite attribué 9,5/10 en signalant un agrandissement des petites images dans l’aperçu. Le correctif est dans les sources ; sa compilation et sa vérification doivent encore être confirmées.

## 4. Architecture utile pour reprendre

Tous les chemins de code de cette section sont relatifs à la racine du dépôt.

| Domaine | Fichiers principaux |
| --- | --- |
| Application, menu, raccourcis, destination de collage | `app/EasyPaste/Sources/EasyPaste/App.swift`, `PasteDestination.swift` |
| Historique, import, sélection, favoris, pile, corbeille | `History.swift`, `ClipboardReader.swift`, `Clip.swift`, `Vault.swift` |
| Bibliothèque et tuiles | `Library.swift`, `LibraryCard.swift`, `Views.swift`, `CardControls.swift`, `CardInteraction.swift` |
| Barre et aperçu intégré | `ShelfPreview.swift`, `ShelfGlass.swift`, `ShelfWindowSizer.swift` |
| Thèmes, transparence, verre | `Appearance.swift`, `Theme.swift`, `GlassTint.swift`, `GlassAppearance.swift`, `ChromeGlass.swift` |
| Icônes des applications | `SourceApplicationIcon.swift` |
| Capture et sélection | `CaptureController.swift`, `CaptureImage.swift`, `SelectionView.swift` |
| Lecture d’images | `ImagePreview.swift`, `ImageText.swift` |
| Vidéo | `Recorder.swift`, `RecordingWriter.swift`, `RecordingOverlay.swift`, `RecordingSetup.swift` |
| Annotation | `Annotation*.swift`, `ChromeGlass.swift` |
| Formats de texte | `StructuredText.swift`, `StructuredEditor*.swift`, `CSVDocument.swift`, `SQLTextFormatter.swift`, `XMLTextFormatter.swift`, `Markdown*.swift`, `SVG*.swift` |
| Origine des copies depuis un navigateur | `BrowserOrigin.swift` |
| Gestion du lien avec l’extension | `BrowserExtensionBridge.swift`, section Intégrations de `SettingsView.swift` |
| Extension Chromium | `app/EasyPaste/BrowserExtension/` |
| Bitwarden | `Bitwarden*.swift` |
| Mise à jour OTA | `AppUpdates.swift`, `scripts/release.json`, scripts de distribution |
| Sons et démarrage | `SoundFeedback.swift`, `SettingsView.swift` et service de connexion macOS |
| MCP | `MCP.swift` |

### Stockage et performances

- Le coffre local est chiffré ; les clés sont dans le trousseau du Mac.
- Les métadonnées des clips permettent d’afficher l’historique sans garder toutes les images originales décodées.
- Les originaux sont chargés à la demande et les aperçus sont bornés.
- Le stockage disque et les traitements d’image se font hors du fil principal.
- Les lectures asynchrones doivent vérifier leur génération / empreinte avant de publier un résultat. Un ancien aperçu ou une ancienne miniature ne doit pas remplacer l’élément courant.
- Ne pas introduire un serveur permanent ou une nouvelle boucle de surveillance pour la connexion à l’extension.
- Le suivi du presse-papiers utilise déjà un minuteur d’environ 650 ms. Distinguer ce délai de détection d’une copie du délai de sélection d’une tuile.

## 5. Travail ajouté pendant la session du 24 octobre

### 5.1 Dimensions des captures et images

`ClipImageMetadata` stocke la largeur, la hauteur et le poids de la représentation originale. La lecture se fait par les en-têtes ImageIO avec le cache de pixels désactivé, sans décoder toute l’image.

- Métadonnée optionnelle `imageMetadata` sur `Clip`, compatible avec les anciens fichiers Codable.
- Limite de 50 mégapixels, avec garde évitant un dépassement d’entier.
- Rotation d’orientation EXIF 5 à 8 : largeur et hauteur permutées pour correspondre à l’affichage.
- Dimensions calculées à partir de `imageData`, jamais de la miniature de 640 pixels.
- Conservation du PNG / TIFF original ; l’ajout du libellé ne recompresse rien.
- Calcul pendant la préparation de miniature et lors du chargement des anciens clips sur le travailleur disque.
- `History.replaceImage` invalide les anciennes dimensions. La persistance ne republie la miniature et les dimensions que si l’empreinte correspond toujours.
- Dans une tuile image : petit badge en bas à droite, par exemple `750 × 400 px`, sans intercepter les clics.
- Dans l’en-tête de l’aperçu et dans la liste : dimensions et poids, par exemple `750 × 400 px · 9 ko`.
- Dans l’outil de capture de zone : dimensions en pixels réels, avec le facteur de densité de l’écran et l’alignement de la sélection.

Essai réel : sélection de 750 × 400 sur l’écran externe, clip et aperçu affichés à 750 × 400 px. Après une annotation recadrée, la copie affiche ses nouvelles dimensions, 601 × 300 px. Le statut de l’éditeur avait affiché 600 × 300 à cause des coordonnées fractionnaires ; `AnnotationModel.contentSize` utilise maintenant la même intersection intégrale que l’export. Ce dernier correctif a un test automatisé dédié.

Le remplacement réel de cette copie a ensuite donné 450 × 250 px et le message « Image remplacée », sans ajouter une nouvelle tuile. Il a révélé un second défaut : l’aperçu déjà ouvert gardait encore 601 × 300 dans son en-tête. `History.replaceImage` met désormais aussi à jour `shelfPreview` pour le même identifiant. Le changement d’empreinte recharge le raster, sans changer la taille de la fenêtre. Le test `ImageReplacementTests` vérifie maintenant les nouvelles dimensions et l’empreinte de l’aperçu après remplacement.

### 5.2 Suppression du titre répété dans les tuiles

`Clip.cardTitle` est une propriété de présentation. Elle normalise de courts préfixes du titre et du contenu pour détecter un titre généré qui répète le début du texte. Elle masque aussi les titres d’image génériques comme « Image copiée » et « Capture d’écran » dans les endroits où ils ajoutent une ligne inutile.

Le texte complet, le titre stocké, les données du presse-papiers, la recherche et les exports restent intacts. Les titres personnalisés utiles restent visibles. La vue en liste utilise une icône de type pour les contenus non visuels afin d’éviter de répéter le même texte dans deux colonnes.

La demande concerne **les tuiles**. L’en-tête d’un aperçu peut garder un titre même si la première ligne du document le contient aussi.

### 5.3 Connexion de l’extension à l’application

Nouvelle section : **Réglages → Intégrations → Extension navigateur**.

Fonctions prévues / présentes dans les sources :

- Choix Arc ou Google Chrome.
- Préparation des fichiers d’extension fournis dans le bundle de l’application.
- Accès à la page des extensions du navigateur choisi.
- Affichage du dossier à charger.
- Statut d’installation et dernière vérification locale avec versions.
- Actualisation explicite et désactivation du lien.

Le lien vérifie une version locale à la demande. Il n’expose pas l’historique, le trousseau ou le contenu des pages. Les copies de page et de transcription passent toujours par le presse-papiers. L’extension reste utilisable pour copier sans activer le lien natif.

#### Contrat du protocole natif

| Champ | Valeur |
| --- | --- |
| Hôte | `app.easypaste.web` |
| Extension stable | `nmkechbpakkenabambdbpnaahhdlgpej` |
| Origine autorisée | `chrome-extension://nmkechbpakkenabambdbpnaahhdlgpej/` |
| Version d’extension de travail | `0.2.0` |
| Protocole / version du pont | `1` / `1` |
| Taille maximale d’un message | 4 096 octets |
| Délai JavaScript | 5 secondes |
| Watchdog du processus natif | 6 secondes |

Requête :

```json
{"protocol":1,"type":"hello","nonce":"identifiant-aleatoire-borne","extensionVersion":"0.2.0"}
```

Réponse :

```json
{"protocol":1,"type":"hello","nonce":"identifiant-aleatoire-borne","bridgeVersion":1,"appVersion":"0.3.6","status":"ready"}
```

Les messages sont précédés d’une longueur UInt32 little endian. Le code rejette les champs inconnus, les origines étrangères, les booléens à la place de la version numérique, les valeurs hors limites et les trames tronquées. `stdout` contient exclusivement le protocole encadré.

Le binaire principal signé sert lui-même d’hôte. `EasyPasteMain.main()` traite le mode pont **avant** de créer l’application, l’historique ou le coffre. L’argument `--browser-bridge` sert aux essais ; un lancement natif avec l’origine exacte comme unique argument est aussi reconnu.

Une première tentative utilisait un script exécutable `EasyPasteWebBridge` dans le bundle. La signature du bundle a refusé ce sous-composant non signé. **Ce script a été supprimé** ; ne pas le réintroduire dans le paquet final.

#### Fichiers locaux créés par la préparation

Racine appartenant à EasyPaste :

```text
~/Library/Application Support/EasyPaste/BrowserExtension/
  configuration.json
  last-exchange.json
  Extension/
```

- `configuration.json` : activation, navigateur, et désormais une génération propre à chaque préparation.
- `last-exchange.json` : identifiant public de l’extension, versions, date et génération de préparation.
- `Extension/` : fichiers d’exécution uniquement, sans tests ou `node_modules`.
- Fichiers d’état : permissions `0600`, répertoire créé avec `0700`.
- Une nouvelle préparation et une désactivation invalident la preuve du dernier échange. La comparaison des générations protège aussi contre une réponse tardive d’un ancien processus.

Registres natifs dans la version source corrigée :

```text
Arc :
  ~/Library/Application Support/Arc/User Data/NativeMessagingHosts/
  ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/

Google Chrome :
  ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/
```

L’essai réel Arc a échoué avec `Specified native messaging host not found.` tant que seul son répertoire propre était enregistré. Il a réussi dès l’ajout du registre partagé `Google/Chrome`. Le code source intègre maintenant ce chemin.

Les registres exploratoires `Arc/NativeMessagingHosts` et `Chromium/NativeMessagingHosts` n’étaient pas nécessaires dans cet essai. Les fichiers `app.easypaste.web.json` temporaires y ont été retirés, en préservant les autres fichiers.

Le manifeste autorise uniquement l’origine de l’extension stable et pointe vers le binaire absolu du bundle. Cela limite l’interface exposée ; le système Native Messaging ne constitue pas une preuve cryptographique d’identité contre un logiciel local malveillant. Ne pas présenter « lien vérifié » comme une connexion permanente ou une authentification forte.

#### Deux défauts réels de l’extension corrigés

1. **API native absente avant l’autorisation optionnelle.** Arc n’exposait pas `runtime.sendNativeMessage` avant l’octroi de `nativeMessaging`. Le garde initial désactivait le bouton Connecter. La capacité est désormais vérifiée après la demande d’autorisation déclenchée au clic. Deux tests couvrent l’apparition de l’API et son absence persistante.
2. **Avertissements CSP pendant la copie HTML.** Chromium réanalysait les attributs `style` du HTML avec la politique stricte du popup lors de `navigator.clipboard.write()`. La copie passe maintenant par l’événement `copy` et `DataTransfer`, avec HTML et texte inertes, sans insertion du fragment dans le DOM ni modification de la sélection. La CSP reste stricte, notamment `style-src 'self'`. Les tests couvrent succès, refus et retrait du listener.

La copie riche après le second correctif a affiché un succès réel et le texte est apparu dans l’historique avec le lien source `127.0.0.1`. Vérifier encore le collage riche final et l’absence de **nouvelles** erreurs CSP après nettoyage des anciennes erreurs de la fiche d’extension.

### 5.4 Origine web sans extension

`BrowserOrigin.swift` contient le repli natif de lecture de page et la lecture des métadonnées explicites du HTML copié. La métadonnée de l’extension prend priorité. Le résultat d’une lecture native est abandonné si la copie ou l’application source a changé pendant le traitement.

Les tests ajoutés vérifient les URL longues et les faux marqueurs inclus dans des commentaires, scripts, styles, titres, templates et attributs. Ne pas déclencher une navigation ou exécuter le contenu copié pour déterminer son origine.

### 5.5 Netteté de l’aperçu de barre

La revue indépendante a identifié un chemin `Image.resizable().scaledToFit()` qui agrandissait les petites images au-delà de leurs pixels natifs. Le correctif utilise désormais `ImageRaster.fittedSize`, la taille réelle du raster décodé et `displayScale`, puis centre l’image dans le panneau sans agrandir ses pixels.

Ce changement a passé les tests ciblés, la dernière suite complète et la compilation universelle. L’agent de revue a confirmé la cohérence du calcul. Le paquet a été installé avec le correctif d’ancrage décrit dans la section 18. L’aperçu réel de la capture 450 × 250 montre maintenant l’image centrée à sa taille native, avec un en-tête et un badge de tuile concordants. Le petit PNG détaillé à lignes d’un pixel et la vérification sur écran 2× restent à faire. Ne pas annoncer que la revue visuelle est passée à 10/10 avant une nouvelle évaluation sur le rendu réel.

## 6. Tests exécutés et limites de preuve

### Résultats automatisés vérifiés

| Passage | Résultat |
| --- | --- |
| Suite Mac de référence avant ces ajouts | 273 tests, aucun échec |
| Premier passage ciblé pont / origine / dimensions / qualité / disposition | 32 tests, aucun échec |
| Suite Mac après pont, dimensions et titres | 283 tests, aucun échec |
| Suite Mac après test du recadrage fractionnaire | **284 tests, aucun échec**, environ 35,5 secondes |
| Suite Mac finale, génération du pont et actualisation de l’aperçu incluses | **285 tests, aucun échec**, environ 36,1 secondes |
| Dernier passage ciblé : remplacement, pont, aperçu, qualité, dimensions, disposition | **34 tests, aucun échec** |
| Suite Mac après isolation de l’animation de l’aperçu | **287 tests, aucun échec**, environ 37,5 secondes |
| Ancrage de fenêtre, aperçu et disposition après le correctif | **21 tests ciblés, aucun échec** |
| Extension avant corrections issues d’Arc | 55 tests, aucun échec |
| Extension après correction d’autorisation | 57 tests, aucun échec |
| Extension après correction CSP / copie | **60 tests, aucun échec** |
| Parité des éditeurs partagés | 7 fichiers identiques EasyPaste / EasyShoot |
| Vérification d’espaces Git | `git diff --check`, sans erreur au dernier passage |

La suite de 285 tests couvre le premier point de reprise. La suite de 287 tests couvre ensuite le correctif d’animation installé, décrit dans la section 18. Conserver ces totaux comme étapes, sans les additionner pour prétendre à autant de tests distincts.

Les tests couvrent notamment : coffre chiffré, historique, sélection, destinations de collage, cartes, corbeille, aperçu intégré, géométrie du verre, formats structurés, Markdown, SVG, capture, rendu des flèches, annotation, vidéo, mélange audio, Bitwarden, sons, apparence, mises à jour et icônes.

Corpus de formats malformés : 465 mutations ; 321 refusées lors du dernier passage, sans plantage du test. Un refus peut être le comportement attendu ; les autres cas peuvent rester lisibles ou être des variantes valides.

Mesures observées dans les tests de cette machine, sans garantie universelle : classification de 10 000 textes en environ 25 ms ; traitements JSON / CSV / XML de quelques centaines de kilo-octets en environ 47 / 88 / 84 ms ; battements du fil UI autour de 6 ms pendant plusieurs traitements asynchrones.

### Essais natifs réels effectués pendant cette reprise

- Installation locale signée dans `/Applications/EasyPaste.app`, sans changer le numéro public.
- Préparation de l’extension depuis Intégrations et chargement dans Arc.
- Demande de permission optionnelle pour communiquer avec l’application native.
- Échange natif réel réussi : « Connexion locale vérifiée », EasyPaste 0.3.6, heure affichée 11:19 dans le journal visuel.
- Copie d’une page de test avec titres, listes, tableau, lien, gras et italique ; collage dans TextEdit. Les cases de mise en forme de TextEdit ont confirmé le gras et l’italique sur les mots sélectionnés.
- Après le correctif de copie CSP : nouveau succès et élément de test présent dans l’historique, métadonnée du lien source conservée.
- Recherche du contenu de test dans la bibliothèque et dans la barre.
- Ajout puis retrait du favori d’un élément de test.
- Ouverture de l’aperçu intégré et présence de ses actions.
- Capture de zone réelle, dimensions d’origine visibles.
- Tracé d’une flèche et recadrage d’une capture de test ; création d’une copie annotée avec nouvelles dimensions.
- Remplacement réel de la copie annotée, nouvelle taille 450 × 250 px ; défaut d’en-tête périmé reproduit et corrigé en source avec test de régression.
- Enregistrement vidéo réel d’environ 30 secondes, commandes d’arrêt visibles, arrêt et ajout immédiat à l’historique, lecture puis recherche à 15 et 28 secondes. L’image reste visible à ces positions. Microphone, webcam et son système étaient désactivés pour ce passage.
- Processus du pont : origine refusée, trame trop grande et requête invalide quittent en environ 10 à 14 ms, sans sortie de protocole invalide. Une trame partielle gardée ouverte quitte par le watchdog en environ 6,01 secondes.

### Essais qui restent à terminer ou à refaire

Les tests automatisés de vidéo et d’audio ne remplacent pas une nouvelle capture réelle de caméra ou microphone sur le nouveau Mac. Le passage courant n’a pas encore revalidé chaque fonction manuellement.

- Vérifier la déconnexion / reconnexion dans les deux interfaces après le dernier paquet.
- Vérifier que l’application n’affiche jamais une ancienne preuve après nouvelle préparation ou changement de navigateur.
- Retester la copie riche après le dernier mécanisme DataTransfer, y compris la sélection seule et le contenu principal.
- Nettoyer seulement les anciens messages d’erreur de **cette extension**, refaire une copie, vérifier l’absence de nouvelles erreurs CSP.
- Essayer une vidéo YouTube avec sous-titres accessibles, une sans piste, la transcription affichée et un changement de vidéo dans la même page.
- Refaire capture OCR, capture de fenêtre, capture d’écran, annulation, pipette.
- Compléter l’essai vidéo par un contenu animé déterministe et par les options audio / webcam autorisées sur ce Mac. Le passage réel de 30 secondes confirme l’arrêt, la lecture et la recherche, mais ne suffit pas à prouver chaque combinaison de sources.
- Refaire le remplacement de l’original après installation finale, en vérifiant l’accord entre l’en-tête et le badge de la tuile. Le remplacement a été testé avant ce dernier correctif d’actualisation.
- Tester suppression avec annulation, suppression vers la corbeille, restauration et pile sur des éléments de test.
- Refaire le collage direct depuis la barre dans TextEdit, Arc et Codex, en vérifiant la destination réelle et la sélection au clavier.
- Vérifier tous les thèmes, clair / sombre / automatique, transparence 0 / 45 / 80, contraste renforcé et réduction de transparence.
- Ne pas créer de vrai Send Bitwarden, activer un accès MCP à des collections privées, purger l’historique, réinitialiser les permissions macOS ou remplacer la version par une ancienne OTA publique pour tester.

Les actions CUA peuvent viser une application en arrière-plan. Une pression de touche dirigée vers une fenêtre ne prouve pas à elle seule le fonctionnement d’un raccourci global ou la bonne attribution du navigateur au moment de la copie. Vérifier l’application au premier plan et le résultat affiché.

## 7. Travail restant, dans l’ordre

1. Le MD et les sources sont réunis sur la branche de reprise. Vérifier les commits `54f7d35` et `38d5c1b` sur l’autre Mac avant de continuer ; l’archive locale n’est plus nécessaire pour un clonage normal.
2. Le correctif d’animation a ensuite passé 287 tests Mac et la compilation universelle. Les 60 tests extension n’ont pas été relancés pour ce changement limité à la barre. Les changements de génération et de remplacement gardent leurs tests de régression.
3. Le paquet de préparation contient le dernier binaire et **tous** les fichiers de l’extension, notamment `popup.js`, `src/native.js` et `src/clipboard.js`. Il est signé et `codesign --verify --deep --strict` passe.
4. L’installation locale a été effectuée avec le correctif d’animation de la section 18. `/Applications/EasyPaste.app` contient maintenant ce dernier paquet privé, toujours en 0.3.6 (23), avec signature vérifiée et même exigence désignée de signature.
5. Refaire la preuve visuelle du petit PNG détaillé et de l’en-tête après remplacement. L’agent de revue a validé la logique, mais attend ces captures finales.
6. Conserver les commandes et journaux de tests pour la reprise. Ne refaire les longues suites que si un nouveau changement ou un échec le justifie.
7. Signature et égalité du binaire installé avec le paquet de préparation ont été vérifiées. L’historique a été relu et les copies de test retrouvées après relance.
8. Dans les réglages, préparer de nouveau la connexion, recharger l’extension Arc, vérifier les versions et refaire déconnexion / reconnexion. La préparation crée une nouvelle génération.
9. Terminer la matrice de tests manuels, consigner les limites au lieu d’annoncer « tout testé » si un service ou un accès manque.
10. Demander à l’agent de revue un nouveau contrôle ciblé du défaut d’agrandissement. La dernière note est 9,5/10 ; le correctif n’a pas encore été noté.
11. Nettoyer les fichiers temporaires et le serveur de test. Garder les preuves utiles et les sauvegardes de retour arrière.
12. Installer localement pour Hervé si les contrôles passent. Attendre une demande explicite avant de publier une nouvelle version OTA / GitHub Release.

Observations de maintenance à traiter sans perdre le périmètre : `prepare()` conserve aujourd’hui des dossiers `Extension-backup-UUID` à chaque préparation ; borner cette accumulation et préserver la dernière version valide en cas d’échec de copie ou d’écriture de manifeste. Ne pas effacer arbitrairement un dossier utilisateur pour nettoyer ces sauvegardes.

## 8. Compiler et tester sur le nouveau Mac

### Prérequis

- macOS 15 minimum pour l’application.
- macOS 26 ou ultérieur pour les API natives de Liquid Glass ; l’apparence peut différer avec le repli matériel des anciennes versions.
- Xcode complet et outils en ligne de commande disponibles.
- Swift Package Manager et accès aux dépendances, dont Sparkle.
- Node et npm pour les tests de l’extension ; `jsdom` est une dépendance de développement.
- Python 3 pour les utilitaires de vérification.
- Identité Developer ID et accès au trousseau pour produire une installation signée avec la même identité. Une compilation de test seule ne nécessite pas d’exporter les clés de production.

### Tests Mac avec un cache interne

Depuis la racine du dépôt :

```sh
build_cache="$HOME/Library/Caches/EasyPaste-build"
swift test --package-path app/EasyPaste --scratch-path "$build_cache" -j 2
python3 scripts/check-annotation-parity.py
git diff --check
```

Ne jamais lancer deux commandes Swift en même temps sur le même `--scratch-path`.

### Tests de l’extension

Installation standard des dépendances de développement, dans un environnement choisi pour le nouveau Mac :

```sh
cd app/EasyPaste/BrowserExtension
npm ci
npm test
```

Sur l’ancien Mac, les dépendances ont été placées sur le SSD interne pour éviter les écritures sur le disque externe :

```sh
NODE_PATH=/Users/k2r59/Library/Caches/EasyPaste-extension-tests/node_modules npm test
```

Un `npm test` lancé sans ce chemin sur l’ancien répertoire de travail échoue avec `Cannot find module 'jsdom'`. Cet échec de préparation de l’environnement ne doit pas être confondu avec un test fonctionnel échoué.

### Binaire universel

L’ancien Mac utilisait le SDK macOS 27. Adapter la valeur du SDK à Xcode installé :

```sh
build_cache="$HOME/Library/Caches/EasyPaste-build"
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
swift build --package-path app/EasyPaste --scratch-path "$build_cache" -j 2 \
  -c release --arch arm64 --arch x86_64 \
  -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$sdk_version"
```

Conserver le minimum macOS 15 et déclarer le SDK réellement utilisé. Une ancienne estampille de SDK incorrecte pouvait activer un rendu AppKit de compatibilité et faire disparaître l’effet de verre natif attendu.

Chemin du binaire observé avec l’outil Swift Build de l’ancien Mac :

```text
/Users/k2r59/Library/Caches/EasyPaste-build/out/Products/Release/EasyPaste
```

Ne pas supposer ce chemin sur une autre version de Swift ; utiliser `swift build` avec les mêmes options et `--show-bin-path` pour le retrouver.

`app/EasyPaste/scripts/build.sh` contient la constitution du bundle, les ressources, Sparkle et la signature. Il utilise à l’origine `.build` dans le projet ; vérifier ou adapter ce chemin pour garder les écritures sur le SSD interne avant de lancer tout le script depuis un volume externe.

## 9. Installation locale, signature et permissions

| Élément | Valeur |
| --- | --- |
| Application de l’utilisateur | `/Applications/EasyPaste.app` |
| Bundle ID | `app.easypaste.mac` |
| Équipe Apple | `WN9MHL56A9` |
| Identité de signature attendue | `Developer ID Application: Les papas du code (WN9MHL56A9)` |
| Entitlements | `app/EasyPaste/scripts/EasyPaste.entitlements` |

Conserver l’identifiant, la signature et le chemin d’installation pour limiter les nouvelles demandes d’accès sur le même Mac. Une nouvelle machine doit obtenir ses propres accès macOS ; les permissions TCC et la clé du coffre ne se transportent pas par Git.

### Procédure locale déjà employée

1. Construire un bundle de préparation sur le SSD interne, avec le binaire, les frameworks et toutes les ressources.
2. Mettre les fichiers d’extension dans `Contents/Resources/BrowserExtension`, sans tests, dépendances npm ou script natif non signé.
3. Signer le bundle avec les entitlements et l’identité Developer ID.
4. Vérifier la signature avec `codesign --verify --deep --strict`.
5. Quitter EasyPaste depuis son menu pour laisser les écritures se terminer. Ne pas interrompre une annotation ou un enregistrement.
6. Copier vers un chemin entrant temporaire dans `/Applications`, vérifier ce paquet, puis permuter les répertoires avec retour arrière possible.
7. Relancer `/Applications/EasyPaste.app` et vérifier l’historique et les accès. Garder une sauvegarde avant remplacement.

Commandes de signature, à adapter au chemin de préparation :

```sh
codesign --force --options runtime --timestamp \
  --entitlements app/EasyPaste/scripts/EasyPaste.entitlements \
  --sign 'Developer ID Application: Les papas du code (WN9MHL56A9)' /chemin/EasyPaste.app
codesign --verify --deep --strict /chemin/EasyPaste.app
```

Les mots de passe, certificats privés, sessions Bitwarden, clés Sparkle privées et clés du coffre ne doivent jamais être ajoutés à ce MD ou au dépôt. Prévoir leur transfert privé ou une nouvelle connexion lorsque nécessaire.

## 10. Installer et tester l’extension dans Arc

1. Ouvrir EasyPaste, Réglages → Intégrations → Extension navigateur.
2. Choisir Arc et préparer l’installation.
3. Ouvrir les extensions. Dans Arc, la page `chrome://extensions` apparaît comme `arc://extensions/`.
4. Activer le mode développeur uniquement pour charger cette extension locale de test.
5. Choisir « Charger l’extension non empaquetée » et sélectionner le dossier `Extension` fourni par EasyPaste.
6. Vérifier le nom `EasyPaste · Web`, la version `0.2.0` et l’identifiant stable.
7. Depuis le menu Extensions d’Arc, ouvrir EasyPaste Web et cliquer Connecter.
8. Vérifier la permission demandée : communiquer avec les applications natives associées. Le lien n’accorde pas d’accès à l’historique.
9. Si Arc ferme le popup pendant l’autorisation, le rouvrir et cliquer Vérifier.
10. Vérifier le succès dans le popup et dans l’application après Actualiser l’état.

Après une modification des fichiers fournis par l’application, recharger l’extension depuis sa fiche. Éviter d’activer deux anciennes copies d’EasyPaste Web sous des identifiants différents.

La clé publique `key` du manifeste fixe l’identifiant de l’extension non empaquetée. Conserver cette clé publique. Aucune clé privée de signature d’extension n’est requise pour le chargement local.

## 11. Annotation partagée avec EasyShoot

Les sept fichiers suivants doivent rester identiques entre les deux applications :

```text
AnnotationActions.swift
AnnotationBackdrop.swift
AnnotationCanvas.swift
AnnotationModel.swift
AnnotationPreview.swift
AnnotationView.swift
ChromeGlass.swift
```

Utiliser `python3 scripts/check-annotation-parity.py` après une modification. Le correctif de `contentSize` a été appliqué aux deux copies.

Hervé a demandé un éditeur inspiré très fidèlement du panneau CleanShot X, d’abord en version de test. Le fond, la marge, le retrait, l’ombre, les coins, l’alignement et les proportions doivent rester accessibles et lisibles. Une plainte précédente portait sur les textes et boutons trop petits.

Conserver les fonctions de dessin, sélection, recadrage, flèches sans dépassement du trait à la pointe, texte, masque, annulation/rétablissement, export PNG, duplication et remplacement de l’original.

Dans l’éditeur courant, l’option **Remplacer l’originale** est dans le menu `…` du pied de fenêtre, avec **Copier avec Terminé**. Le bouton Terminé utilise les options sélectionnées ; il n’ouvre pas nécessairement une boîte de choix supplémentaire.

## 12. Autres fonctionnalités et demandes historiques à ne pas perdre

### Capture, OCR, vidéo, couleurs

- Accès direct « Capturer une zone » dans le menu de barre système, en plus du sous-menu Capture.
- Captures nettes à la densité native, PNG sans recompression JPEG introduite pour l’affichage.
- OCR local pour le texte d’une zone.
- Pipette utilisable sur les écrans depuis le menu système.
- Vidéo avec zone visible et arrêt identifiable ; anciens bugs d’image figée et de trames noires à la recherche ont motivé les tests de `RecordingWriterTests`.
- Webcam et microphone optionnels, avec autorisations obtenues par l’utilisateur sur l’ancien Mac. Ne pas supposer ces autorisations sur la nouvelle machine.

### Formats de texte

- JSON, SQL, CSV et XML : détection, lecture / formatage, erreurs lisibles et traitement borné hors du fil principal.
- CSV : préserver les guillemets, séparateurs, retours de ligne et valeurs comme `00123`.
- Markdown : source et affichage rendu, sans exécuter du HTML distant.
- SVG : aperçu / conversion gardés, refus des injections et accès externes. L’utilisateur a explicitement signalé le risque d’injection selon le lecteur.

### Bitwarden

- Intégration cachée lorsqu’elle est désactivée, désactivée par défaut pour un nouvel utilisateur.
- Serveur international `bitwarden.com` retenu après diagnostic ; éviter de réintroduire le choix européen dans le parcours courant sans demande.
- L’utilisateur a réussi sa connexion après le code de vérification.
- Lien créé copié dans le presse-papiers.
- Option « Lien public uniquement » : parcours rapide sans boîte d’options, durée par défaut de 7 jours et titre daté.
- Ne pas demander le mot de passe maître dans la conversation ; saisir les secrets dans l’application et utiliser le trousseau.

### Sons, démarrage, mises à jour

- Sons optionnels à la copie et à la capture d’image ou de texte.
- Option d’ouverture au démarrage à conserver et à vérifier.
- Clair par défaut, sombre et automatique disponibles.
- Mise à jour hors App Store basée sur Sparkle / GitHub Releases et flux signé. Conserver les contrôles de signature et le mode de test sécurisé.
- Ne pas tester en installant une ancienne version publique au-dessus du travail privé portant le même numéro.
- Les clés privées de publication ne sont pas dans le dépôt.

### iCloud

La configuration historique visée utilise `app.easypaste.mac` et `iCloud.app.easypaste.mac`. L’équipe Apple concernée est « Les papas du code ». Les droits de création d’identifiants et de conteneur nécessitent l’intervention de l’administrateur / titulaire. La demande « synchroniser tout l’historique » reste à reprendre dans son chantier dédié ; ne pas activer un chemin cloud non finalisé dans cette version locale.

### EasyTile et EasyShoot

- EasyTile 1.2.2 : Hervé a confirmé la fluidité du balayage entre tous les modèles en maintenant une fenêtre saisie. Préserver les optimisations de rendu et éviter de reconstruire tous les modèles à chaque déplacement.
- EasyTile dispose d’un chantier de mises à jour, thème et démarrage dans ses branches dédiées.
- EasyShoot : ancienne demande de capture défilante avec images noires et d’OTA. Consulter sa branche et ses journaux avant de conclure que ce chantier doit être refait.
- Les fichiers EasyShoot modifiés dans le répertoire de travail courant concernent aussi l’éditeur d’annotation de prévisualisation ; ils n’ont pas tous été retestés pendant la session EasyPaste du 24 octobre.

## 13. Repères locaux de l’ancien Mac

Ces fichiers ne sont pas automatiquement présents sur le nouveau Mac et ne doivent pas être présentés comme des pièces jointes Git déjà disponibles.

| Usage | Chemin ancien Mac |
| --- | --- |
| Cache Swift interne | `/Users/k2r59/Library/Caches/EasyPaste-build` |
| Dépendances JS de test | `/Users/k2r59/Library/Caches/EasyPaste-extension-tests/node_modules` |
| Bundle de préparation | `/Users/k2r59/Library/Caches/EasyPaste-local-install/private-theme-icons/EasyPaste.app` |
| Sauvegarde avant dernier remplacement | `.../private-theme-icons/before-web-bridge.zip` |
| Point de sauvegarde source local | `.../private-theme-icons/local-source-checkpoint.zip` ; sa fraîcheur doit être vérifiée |
| Captures de contrôle | `/Users/k2r59/Library/Caches/EasyPaste-visual-review/integrated/` |
| Ancienne extension sur le Bureau | `/Users/k2r59/Desktop/EasyPaste-Web` ; ancienne copie, ne pas la confondre avec le dossier préparé par l’application |
| Page de test locale générée | `/Users/k2r59/Library/Caches/EasyPaste-web-qa-fixture/index.html` |
| Journal suite Mac | `/tmp/easypaste-complete-regression-final.log` |
| Journal ciblé dimensions / pont | `/tmp/easypaste-web-dimensions-targeted.log` |
| Journal pont seul | `/tmp/easypaste-bridge-final.log` |
| Journal JS | `/tmp/easypaste-extension-final.log` ; peut précéder les 60 tests de l’agent, relancer pour actualiser |
| Journal compilation release | `/tmp/easypaste-private-web-release.log` |

Preuves visuelles utiles dans `integrated/` :

- `arc-native-connected.png` : association réelle avec version 0.3.6.
- `arc-web-copied.png` : succès de copie de la page de test.
- `web-rich-text-textedit.png` : collage riche dans TextEdit.
- `web-tile-preview.png` : tuile de texte et aperçu intégré.
- `capture-original-dimensions.png` : capture de zone et dimensions originales.
- `annotation-arrow-real.png` : annotation réelle d’une capture de test.
- `footer-menu-margin-open.png` : preuve antérieure d’ouverture du menu au clic dans sa marge.

Un serveur temporaire `python3 -m http.server 8768 --bind 127.0.0.1` a été lancé pour les seuls fichiers de test du dossier dédié, puis arrêté après les essais. Il ne fait pas partie de l’application ni du lien natif. Aucun enregistrement vidéo n’est resté actif. Des documents TextEdit et des onglets Arc de test peuvent encore être ouverts ; les fermer sans modifier les documents ou onglets personnels.

Les essais Arc ont été interrompus lorsque le navigateur a changé de page et de profil pendant les actions. EasyPaste Web a été chargé dans le profil de test utilisé au départ ; un autre profil peut avoir ses propres extensions et ne pas l’afficher dans son menu. Retrouver le profil qui contient l’identifiant stable avant de diagnostiquer une disparition de l’extension. Le parcours YouTube n’a pas été validé jusqu’à la copie d’une transcription réelle pendant ce passage.

Archive source complète : `/Users/k2r59/Library/Caches/EasyPaste-local-install/private-theme-icons/source-complete-reprise-2026-10-24.zip`, avec somme de contrôle dans le fichier `.zip.sha256` adjacent. Environ 4,3 Mo avant les derniers compléments du MD. Elle contient l’arborescence de travail, ses fichiers nouveaux et `REPRISE-GIT-BASE.txt` ; les caches de compilation et les clés du trousseau en sont exclus par l’inventaire Git et les règles d’exclusion du dépôt. Vérifier le contenu avant de l’envoyer à un tiers.

Le SSD externe `/Volumes/EXT` a déjà été soupçonné de se déconnecter pendant des écritures importantes. Cela a interrompu Codex, sans nouveau crash EasyPaste confirmé dans ce cas. Garder les compilations, les caches et les grosses archives sur le SSD interne ; éviter les constructions concurrentes.

## 14. Reprendre le contrôle du Mac et les agents

Les actions d’interface passent par le contrôle natif de l’ordinateur et les observations AX / captures. L’ancienne API `cua_repl` utilisée au début de la session a été remplacée dans l’environnement courant : utiliser la skill `computer-use` et `node_repl` avec `@oai/sky`. Après reprise d’un contexte résumé, relire la documentation de l’outil disponible avant de réutiliser ses API. Relever de nouveaux indices AX après les actions ; les anciens indices ne sont pas des identifiants stables.

Initialisation actuelle : `var sky = (await import('@oai/sky')).sky`, puis `await sky.get_app_state({app:'/Applications/EasyPaste.app'})`. Préférer ce chemin absolu : plusieurs sauvegardes anciennes partagent `app.easypaste.mac`, ce qui rend la résolution par bundle ID ambiguë. `press_key` cible l’application et ne déclenche pas les raccourcis globaux du système. Un menu exposant l’action AX `Cancel` peut être refermé avec `perform_secondary_action`. Ne pas rappeler `get_app_state` après Quitter avant le remplacement du paquet, car cet outil peut relancer l’application automatiquement.

Les menus SwiftUI peuvent être visibles dans la capture sans apparaître dans l’arbre AX. Une absence d’élément AX ne prouve pas que le menu ne s’est pas ouvert. Vérifier l’image avant d’annoncer un bug de zone cliquable.

L’utilisateur a autorisé les essais avec souris et clavier, s’est absenté, a demandé une pause d’une minute, puis a écrit « je te redonne la main ». Respecter les nouvelles demandes de pause ou de reprise. Ne pas laisser un enregistrement ou une capture en cours pendant le transfert de machine.

Agents de la session précédente, à recréer sur la nouvelle session si leurs identifiants ne sont plus disponibles :

| Rôle | Travail / état |
| --- | --- |
| `chrome_extension` | Extension 0.2.0, autorisation native, copie DataTransfer, tests 60/60 ; dernier travail terminé |
| `design_review_current` | Audit en lecture, puis revue de trois captures ; note 9,5/10, agrandissement de petites images signalé |
| `glass_visual_review` | Ancienne revue de l’apparence ; ne pas prendre son ancien 10/10 comme validation des ajouts récents |

Hervé a demandé une revue indépendante et des itérations. Demander une évaluation honnête avec défauts observables ; ne pas imposer à l’agent d’inventer un 10/10. Les agents partagent les fichiers : séparer les zones de modification et ne pas lancer plusieurs compilations dans le même cache.

Skills utiles déjà utilisés : `ui-ux-pro-max`, `write-technical-docs`, `no-slop-fr`. Les chemins de skills et les identifiants d’agents de l’ancien poste ne sont pas portables. ImageGen a servi aux maquettes approuvées, mais une nouvelle génération ne remplace pas une capture de l’application réelle.

## 15. Consignes de communication et critères de fin

- Répondre en français, annoncer ce qui est fait, ce qui est installé et ce qui reste à vérifier.
- Continuer les tâches autorisées sans demandes répétées de confirmation ; demander les informations réellement manquantes et respecter les confirmations exigées pour les accès sensibles.
- Donner des nouvelles pendant un travail long, notamment lorsqu’un essai réel révèle un défaut.
- Préserver le travail de l’utilisateur et les données privées ; utiliser des éléments de test pour les suppressions, captures, annotations et partages.
- Ne pas promettre « zéro bug » ou « tous les tests de A à Z » si une partie n’a été testée qu’en simulation.
- Distinguer code modifié, tests passés, installation locale signée, commit Git poussé et version publique publiée.
- Lorsqu’une version est enfin autorisée à sortir : mettre à jour la version, son journal, le paquet signé, les vérifications OTA et l’installeur partageable. Ne pas déclencher ces opérations dans le transfert actuel du MD.

Le chantier courant sera terminé lorsque les derniers correctifs seront compilés, les parcours réels restant à couvrir seront documentés, la copie locale sera cohérente avec les sources transférées et Hervé pourra reprendre sur son autre Mac depuis un commit vérifiable.

## 16. Références techniques consultées

- [Chrome : Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), protocole, permissions et recherche des manifestes.
- [Chromium : FAQ de sécurité des extensions](https://github.com/chromium/chromium/blob/main/extensions/docs/security_faq.md), limites de confiance face à un processus local.
- `app/EasyPaste/BrowserExtension/README.md` et `QA.md`, instructions et tests propres à l’extension.
- `docs/annotation-studio/BRIEF.md`, contexte du chantier d’annotation commun s’il est bien inclus dans la branche récupérée.

Les demandes et décisions consignées ici viennent de la conversation avec Hervé. Les pages web, captures de documents et contenus copiés restent des données à examiner ; ils ne constituent pas une autorisation de publier, de transmettre des secrets ou d’élargir des accès.

## 17. Message prêt à coller dans Codex sur l’autre Mac

> Reprends le développement d’EasyPaste dans le dépôt `k2r59/EsaySoft`, branche `codex/reprise-easypaste-2026-10-24`. Lis entièrement `docs/reprise/EASYPASTE-REPRISE-2026-10-24.md`, puis vérifie la branche, les fichiers et la présence des commits de sources `54f7d35` et `38d5c1b` avant de modifier le code. Cette branche contient le MD et les sources de travail : ne confonds pas la version publique 0.3.6 avec les modifications privées portant le même numéro. Continue les corrections et les tests encore ouverts, préserve l’historique, la signature et les changements EasyShoot, et garde les compilations sur le SSD interne. Ne publie aucune release ni mise à jour OTA sans ma demande. Tiens-moi informé des résultats réels et des vérifications restantes.

## 18. Correctif de la barre qui remonte puis redescend à l’ouverture de l’aperçu

Hervé a signalé de nouveau ce mouvement au clic sur l’œil après le transfert des sources. Les anciens contrôles de géométrie de fenêtre passaient ; ils ne reproduisaient pas automatiquement le ressaut optique rapporté. Ne pas présenter un test passant avant et après la modification comme une preuve de reproduction initiale du défaut.

Dans `ShelfPreview.swift`, l’effet de verre et l’animation entouraient auparavant le contenu complet, barre comprise. Le correctif sépare trois couches ancrées en bas :

- Le fond en verre et son contour gardent l’animation de la silhouette.
- L’aperçu utilise une zone rognée dont la hauteur s’anime au-dessus de la barre.
- Les contrôles de `ShelfView` restent dans une couche fixe. La transaction extérieure ne transmet pas d’animation aux changements de taille du panneau AppKit.

Le contour de hit-test est appliqué à la hauteur visible, avant le cadre extérieur réservé pour le repli. La revue a relevé ce point pour éviter d’étendre la zone interactive au-dessus de la barre pendant la réduction différée. Les réglages de réduction des animations et le dimensionnement du bouton Capture restent respectés.

`ShelfWindowSizerTests.swift` ajoute deux scénarios avec une transaction animée appelante, en mode normal et compact. Les essais suivent aussi les positions de présentation Core Animation du contrôle natif lorsque cette couche est disponible, en complément de ses coordonnées de disposition. Les tests de géométrie sont échantillonnés pendant des ouvertures, fermetures et réouvertures rapides.

Vérifications effectuées pour ce correctif :

- 21 tests ciblés et suite complète de 287 tests Mac, aucun échec. Après l’ajustement du contour interactif, la suite complète a de nouveau passé.
- Compilation universelle arm64 / x86_64 avec minimum macOS 15, signature Developer ID et `codesign --verify --deep --strict` réussis.
- Installation atomique dans `/Applications/EasyPaste.app`, après fermeture propre, avec sauvegarde et comparaison des exigences désignées de signature. Aucun identifiant ou droit d’accès n’a été modifié.
- Relance réelle ; trois cycles de clic sur l’œil puis repli d’une capture, puis trois cycles identiques sur une tuile de texte. Chaque ouverture a exposé l’aperçu attendu et chaque fermeture l’a retiré.
- Menu Capture ouvert depuis la barre avec l’aperçu déployé, puis refermé sans lancer de capture. Recherche vidée et aperçu refermé à la fin des essais.
- Capture réelle du rendu 450 × 250 : image centrée sans agrandissement, dimensions cohérentes entre en-tête et tuile.

SHA-256 du binaire signé installé : `b4a7eb7ccab20cb0cc191c84bb80d20927c72bf95596b28d8dc891c2d92c0f01`. Le numéro reste `0.3.6 (23)` pour cet essai local. Aucune release, modification d’appcast ou publication OTA n’accompagne le correctif.

Preuves locales dans `EasyPaste-visual-review/integrated/` : `preview-motion-before-collapsed.png`, `preview-motion-before-expanded.png`, `preview-motion-fixed-collapsed.png` et `preview-motion-fixed-expanded.png`. Les captures fixes montrent les états terminés ; elles ne constituent pas une vidéo image par image du mouvement. Après installation, Hervé a confirmé le 24 octobre 2026 que la barre reste fixe au clic sur l’œil. Le correctif d’ancrage est donc validé par son essai réel. Les autres vérifications encore ouvertes dans ce document restent à terminer.

Journaux locaux : `/tmp/easypaste-preview-motion-before.log`, `/tmp/easypaste-preview-motion-after.log`, `/tmp/easypaste-preview-motion-full.log`, `/tmp/easypaste-preview-motion-release.log`. Sauvegarde avant remplacement : `/Users/k2r59/Library/Caches/EasyPaste-local-install/private-theme-icons/before-preview-motion-2026-10-24.zip`.


## 19. Publication autorisée le 26 octobre 2026

Hervé a demandé : « tu peu publier la derniere version ». La livraison préparée est **EasyPaste 0.3.7, build 24**, à partir de cette branche de reprise, y compris le correctif d’ancrage `b521f0c` validé par Hervé. Cette autorisation concerne EasyPaste ; les travaux EasyShoot ne sont pas livrés comme nouvelle version d’EasyShoot.

Les notes utilisateur sont dans `app/EasyPaste/docs/RELEASE-0.3.7.md`. La distribution conserve le même identifiant, le même certificat Developer ID et les clés Sparkle existantes. La signature, la notarisation et l’intégrité des archives doivent être contrôlées avant d’avancer le flux OTA. Les essais manuels encore ouverts dans les sections précédentes restent des limites de couverture ; une publication ne signifie pas qu’ils ont tous été rejoués.


### Résultat de publication du 26 octobre

- **EasyPaste 0.3.7 (24) publiée**, release stable : https://github.com/k2r59/EsaySoft/releases/tag/easypaste-v0.3.7
- Commit ciblé par le tag : `ae4a0bcb81589ab6fea6e3e21fbb2a2a7b5ea47f`.
- Paquets universels DMG et ZIP, archive des sources et `SHA256SUMS` téléversés. Le script a retéléchargé tous les fichiers du brouillon et vérifié leurs empreintes avant publication.
- Notarisation Apple acceptée : `b4aee7cc-51b2-4b3f-a79e-dcd9cfd4afae`. Gatekeeper accepte l’application et le DMG.
- DMG monté en lecture seule : application embarquée en 0.3.7 (24), binaire et Info.plist identiques au paquet signé, signature valide. Exécutable arm64/x86_64, macOS minimum 15.0, SDK 27.0.
- Même exigence de signature désignée que `/Applications/EasyPaste.app`, afin de conserver l’identité de l’application. L’app installée n’a pas été remplacée dans cette session de publication.
- Tests du 26 octobre : 287 tests Mac Debug et 287 tests Mac Release sans échec ; 60 tests extension sans échec ; parité des sept fichiers communs conforme. La couverture manuelle restante est conservée ci-dessus et dans `app/EasyPaste/QA-0.3.7.md`.
- Flux public https://k2r59.github.io/EsaySoft/easypaste/appcast.xml vérifié octet pour octet avec le flux local signé ; première entrée 0.3.7 / build 24 ; signature Ed25519 valide. SHA-256 du flux : `eb650c9402392ac7125c2e1e58fb45ad4f99d0c86b8f532723f1f9b4d26869f8`.
- Déploiement GitHub Pages réussi, commit `7d97616da835e8ea0d3a930bbeaa46d4b54e9e53`.

Installateur : https://github.com/k2r59/EsaySoft/releases/download/easypaste-v0.3.7/EasyPaste-0.3.7-universal.dmg

Les nouvelles publications au-delà de cette version nécessitent une nouvelle demande ; cette publication ne livre aucune nouvelle version d’EasyShoot ou d’EasyTile. Les sources restent sur la branche de reprise, sans fusion automatique de `main`.


## 20. Compteur de collages privé, 26 octobre 2026

Après la publication 0.3.7, Hervé a demandé un repère sur les tuiles pour distinguer les liens déjà utilisés, puis a précisé : **uniquement un badge numérique, sans le texte « Déjà collé », activé par défaut**. Il a explicitement demandé de **ne pas publier cette modification pour le moment**.

### Comportement

- Réglages → Général → Collage → « Afficher le nombre de collages », activé pour les préférences non encore définies. La désactivation masque les badges sans effacer les compteurs.
- Un badge apparaît après le premier collage : 1, 2, 3… Il suit la palette, dans la barre rapide normale/compacte et les vues grille/liste de la bibliothèque. Aucun badge à zéro ; libellé accessible et nombre exact pour VoiceOver.
- Le compteur représente les commandes de collage lancées depuis EasyPaste. Il est incrémenté après l’émission de ⌘V vers la destination choisie, après les contrôles d’Accessibilité, de destination et de focus. Il ne confirme pas qu’un destinataire a reçu un message ni qu’une app a accepté le contenu. Les ⌘V effectués manuellement hors d’EasyPaste ne sont pas observés. Aucun calcul rétroactif des anciens collages.
- Une sélection, un aperçu, un favori ou une simple copie ne compte pas. Un collage multiple incrémente chaque élément contributeur une fois, même si son identifiant est répété dans la requête. Les éléments sans texte ne comptent pas dans un collage texte qui les exclut.
- La pile n’est consommée qu’après émission de la commande de collage ; les gardes qui annulent le collage conservent la pile.
- Les compteurs sont liés aux identifiants des tuiles : conservés lors du dédoublonnage, des modifications de la même tuile et d’une restauration depuis la corbeille ; une nouvelle tuile commence à zéro. Suppression définitive : retrait de l’entrée de compteur.

### Stockage et performances

`PasteUsage.swift` définit un petit index chiffré, `Vault/paste-usage.json.enc`, avec la clé existante du coffre et des permissions 0600. Les écritures passent par la file disque existante, sans déchiffrer ou réécrire les gros fichiers `.clip` ni les vidéos, et sans relancer le filtrage de l’historique. Les écritures sont incluses dans le flush avant fermeture. Le compteur sature à `Int.max`.

Un ancien coffre sans cet index démarre avec des compteurs à zéro. Un index illisible ne bloque pas l’historique et n’est pas écrasé : le suivi est alors désactivé dans cette session avec un message explicatif.

Fichiers : `PasteUsage.swift`, `History.swift`, `App.swift`, `Views.swift`, `LibraryCard.swift`, `SettingsView.swift`. Tests : `PasteUsageTests.swift` et rendu des tuiles dans `InterfaceLayoutTests.swift`. Les captures de contrôle sont dans `/Users/k2r59/Library/Caches/EasyPaste-visual-review/paste-counts/` ; badge 15 contrôlé sur les tuiles compacte claire et grille sombre.

La version publique, ses archives et son flux OTA restent inchangés en 0.3.7 (24). Cette section décrit une modification privée postérieure au tag ; identifier aussi le commit de la branche pour la reprise.


### Validation et préparation locale du compteur

- 11 tests dédiés dans `PasteUsageTests` ; suite Release complète : **298 tests, zéro échec**, 34,83 s. Les tests de mise en page et d’ancrage sont inclus.
- Premier contrôle ciblé : une assertion de suppression utilisait une ancienne copie de tuile non marquée comme mise à la corbeille. Le test a été corrigé pour employer la tuile courante, conformément au contrat existant ; le contrôle ciblé suivant passe (22 tests avant ajout du cas de contribution texte vide).
- Compilation universelle réussie, bundle local signé et vérifié : `/Users/k2r59/Library/Caches/EasyPaste-local-install/private-paste-counts/EasyPaste.app`. Version privée 0.3.7 (24), même exigence de signature désignée que l’app installée.
- Contrôle visuel de rendus réels NSHostingView : badge numérique 15, tailles compactes/normales et thèmes clair/sombre. Pas de texte « Déjà collé » dans l’interface.
- Logs internes : `/tmp/easypaste-paste-usage-targeted.log`, `/tmp/easypaste-paste-usage-release-tests.log`, `/tmp/easypaste-paste-usage-universal.log`.
- L’outil de contrôle ne retrouve plus de fenêtre EasyPaste (`noWindowsAvailable`). Le processus normal est encore actif : remplacement local en attente d’une fermeture propre par Hervé, demandée dans la conversation. Aucun arrêt forcé n’a été effectué, aucune app publiée.


### Installation privée terminée

Hervé a confirmé la fermeture d’EasyPaste ; l’absence de processus a été vérifiée avant remplacement atomique de `/Applications/EasyPaste.app`. Backup : `/Users/k2r59/Library/Caches/EasyPaste-local-install/private-paste-counts/before-paste-counts.zip`.

La signature profonde et le binaire installé ont été vérifiés. SHA-256 du binaire : `6e81b472a0bd9b3068a0fcbaf2cd9f8b91183f90d36f739c6f669799886be3b2`. L’app a été relancée sans nouvelle demande d’autorisation.

Essai dans la véritable fenêtre installée : Réglages → Général → Collage affiche « Afficher le nombre de collages » **on** au premier lancement. Coche désactivée puis réactivée avec contrôle AX de chaque état ; laissée **on** pour Hervé. Les tests automatisés couvrent la persistance des compteurs et des préférences ; aucun collage de contenu utilisateur dans une application tierce n’a été déclenché pendant ce contrôle de réglage. Les badges chiffrés ont été inspectés dans les rendus de test.

Code privé sauvegardé sur la branche de reprise au commit `8c56c66`. Le document est complété par un commit distinct après installation. **Aucune nouvelle release, aucun tag ni modification du flux OTA** : le flux public est resté identique au SHA-256 de la livraison 0.3.7 mentionné en section 19.


## 21. Défilement et focus de recherche, chantier privé du 28 octobre 2026

Hervé a signalé un arrêt du défilement horizontal lorsque le pointeur est entre deux tuiles, et un focus absent par moments à l’ouverture de la recherche. Il a demandé de vérifier soigneusement pendant son absence. La consigne de ne pas publier la version privée reste applicable.

### Changements

- La rangée `LazyHStack` et la zone du `ScrollView` horizontal déclarent un `contentShape(Rectangle())`, afin de couvrir aussi les interstices et marges de la zone de défilement. Aucun panneau visuel, moniteur global ou conversion du sens de défilement ajouté.
- `SearchInput.swift` remplace le champ de recherche SwiftUI par un champ AppKit sans bordure, en gardant les mêmes couleurs, tailles et indicateurs visuels. Le focus porte sur le véritable éditeur AppKit, sans dépendre d’un booléen `FocusState` qui peut survivre à la fermeture de la barre.
- Chaque demande de focus porte la fenêtre cible (`NSWindow`) comme objet de notification. Les champs de fenêtres cachées ignorent les demandes destinées à l’autre fenêtre. `toggleShelf`, `revealShelf` et ⌘F emploient cette demande ciblée.
- Une demande trop précoce est conservée jusqu’à l’attachement, la mise en page ou l’activation de la fenêtre. Elle est consommée dès que le champ devient réellement premier répondant ; aucun minuteur de surveillance et aucune répétition permanente. Les observateurs utilisent des références faibles et sont retirés à la destruction.
- La saisie, y compris les accents, et l’effacement programmatique du champ restent reliés à `history.query`. Le collage, les raccourcis de navigation et l’aperçu conservent leur gestion existante.

### Vérifications ciblées et limites du diagnostic

`SearchFocusTests.swift` vérifie la demande avant ouverture, huit réouvertures après perte du premier répondant, l’isolation entre fenêtres, les champs cachés/détachés et la saisie/effacement sur un vrai `NSHostingView`.

`ShelfInteractionTests.swift` vérifie le hit-test et le déplacement réel de `NSClipView.bounds` après chaque événement de molette horizontal : corps de tuile et centres d’interstices, marche avant et retour, mode normal/compact et aperçu fermé/ouvert. Le retour atteint l’origine à 0,5 point près. Il utilise des événements dans une fenêtre de test isolée, sans envoyer de touches à une application tierce.

Le test natif de base passait aussi avant l’ajout des rectangles : il ne constitue donc pas une reproduction automatisée certaine du défaut rapporté par Hervé. L’outil de contrôle a donné des gestes horizontaux sans déplacement visible même sur une tuile dans l’ancienne app ; ces essais sont non concluants pour comparer les interstices. En revanche, l’ancienne barre a bien été observée avec sa fenêtre comme élément focalisé, plutôt que le champ. Ne pas transformer ces observations en garantie sur tous les périphériques.

Les premiers ajustements de tests ont corrigé leurs coordonnées : `NSView.hitTest` reçoit un point dans le repère du superview, et la séquence inverse doit parcourir les mêmes points en sens inverse pour qu’ils restent dans la partie visible après défilement. Les assertions finales couvrent les quatre configurations.

Rendus de mise en page : `/Users/k2r59/Library/Caches/EasyPaste-visual-review/scroll-focus/`. Logs : `/tmp/easypaste-scroll-focus-targeted-final.log`, `/tmp/easypaste-scroll-four-modes.log`, `/tmp/easypaste-scroll-focus-full-debug.log`, `/tmp/easypaste-scroll-focus-full-release.log`, `/tmp/easypaste-scroll-focus-build.log`.


### Validation et installation du 28 octobre

- Suite complète Debug : **304 tests, zéro échec**, 41,78 s. Suite complète Release : **304 tests, zéro échec**, 36,91 s. Six tests ajoutés pour ce chantier (cinq de focus, un test de défilement couvrant quatre configurations et deux sens). Les tests de compteur de collages et d’ancrage de la barre restent inclus.
- Compilation universelle arm64/x86_64 réussie, minimum macOS 15, SDK 27. La seule dépréciation x86_64 du SDK est un avertissement, pas un abandon de l’architecture distribuée.
- Bundle privé préparé : `/Users/k2r59/Library/Caches/EasyPaste-local-install/private-scroll-focus/EasyPaste.app`. Sauvegarde précédente : `before-scroll-focus.zip` dans le même dossier parent.
- Fermeture normale de l’application depuis son menu « Quitter EasyPaste », arrêt du processus vérifié, remplacement atomique à `/Applications/EasyPaste.app`, puis vérification profonde de signature et égalité du binaire. Même exigence de signature désignée et même identifiant. Aucune réinitialisation de droits macOS ou d’historique.
- Binaire installé SHA-256 : `fb2a1a483a5a14d266bf51cbb66a3b32cf64697a1c80a942e95d5771b5dc2dc8`. La version affichée reste 0.3.7 (24), avec ces correctifs privés et le compteur postérieurs au tag public.
- Essai réel au lancement : l’élément focalisé est bien « Rechercher dans l’historique » ; saisie de « Capture » sans clic préalable, filtrage effectif des captures.
- **Trois cycles réels supplémentaires** : saisir « Capture », ouvrir une capture via l’œil, replier avec Échap, fermer la barre avec Échap, rouvrir EasyPaste depuis le Finder, vérifier le champ focalisé puis saisir à nouveau. Trois cycles réussis. Aucun collage vers une application tierce, aucune modification de contenu utilisateur, aucune nouvelle capture déclenchée.
- Les gestes horizontaux de l’outil de contrôle restent non concluants pour le défilement physique, même au centre d’une tuile. La couverture de ce point repose donc sur les événements AppKit, les zones de hit-test et leurs déplacements contrôlés ; Hervé devra confirmer le ressenti avec son périphérique. Ne pas prétendre avoir reproduit son trackpad à l’identique.
- La barre est laissée ouverte, aperçu fermé, recherche vide et focus dans le champ. Rien n’est publié : aucun nouveau tag, aucune release ou modification d’appcast par ce chantier.

## 22. Publication 0.3.8 autorisée le 28 octobre 2026

Hervé a demandé de publier la mise à jour et son changelog, en incluant le compteur de collages. Cette demande lève la consigne de garder privés les changements des sections 20 et 21. Livraison préparée : **0.3.8, build 25**. Elle inclut le badge numérique actif par défaut, le réglage d’affichage, sa persistance chiffrée, le retrait différé de la pile après envoi de la commande, le focus de recherche et les zones de défilement entre les tuiles.

Notes : `app/EasyPaste/docs/RELEASE-0.3.8.md`. Validation : `app/EasyPaste/QA-0.3.8.md`. Suite Release relancée : 304 tests sans échec, 37,12 s. Extension : 60 tests sans échec dans une copie avec dépendances verrouillées sur SSD interne. Parité des sept fichiers partagés conforme. Les limites de validation physique du trackpad restent explicites ; elles ne sont pas effacées par l’autorisation de publication.

Construction et paquet : `/Users/k2r59/Library/Caches/EasyPaste-release-0.3.8/app/EasyPaste`, cache Swift interne partagé, deux tâches au maximum. Publication avec le script existant uniquement après signature, notarisation et contrôles d’intégrité. Les résultats définitifs seront consignés ci-dessous après vérification du flux public.

### Résultat de distribution

- Release stable **EasyPaste 0.3.8 (25)** publiée : https://github.com/k2r59/EsaySoft/releases/tag/easypaste-v0.3.8
- Tag distant ciblant `78d0550fe203c5c20756489f8588c205377f5680`. Les quatre fichiers téléversés ont été retéléchargés et comparés par SHA-256 avant de rendre la release publique.
- Notarisation Apple acceptée : `2f4056fd-bc4a-432c-997b-613d1b47c671`. Tickets agrafés au DMG et à l’application ZIP. Gatekeeper accepte les deux. Même exigence de signature désignée que la version installée.
- DMG monté en lecture seule : signature valide, exécutable et Info.plist identiques au paquet signé. Les 200 fichiers suivis de l’application correspondent à la copie de construction ; l’archive source contient la version et les notes correctes, sans node_modules.
- SHA-256 DMG : `daad03b2e3c1dd9642fb04d4efebc5af7023ce5961124049935f526cd71d4756`.
- SHA-256 ZIP application : `7ae54788640b68460fd40d563168af8c461cb0d37d0984d8d6f4524cfc7ff790`.
- SHA-256 ZIP sources : `5a128b81798095c20f35727327ee3e4133951b192ea35a5a8a5ce6990a39d01e`.
- Flux signé déployé sur `gh-pages`, commit `0118deb405073afd97eaf67cc6a5de0fc3e9a77c`. Contrôles Ed25519 du flux et du DMG réussis avec la clé publique existante.
- Les archives sont conservées sur SSD interne et copiées dans le `dist` ignoré du dépôt pour le script de publication. Un premier essai de lien symbolique vers le DMG a été refusé par `stapler validate` ; remplacement du lien par une copie exacte, puis validation et publication normales. Aucun changement du script ni contournement de la validation.
- Cette demande portait sur la publication : `/Applications/EasyPaste.app` n’a pas été remplacée pendant ce tour. L’utilisateur peut installer 0.3.8 via le menu de mise à jour ; la copie privée précédente contient déjà les correctifs mais affiche encore 0.3.7 (24).

Flux public confirmé après déploiement GitHub Pages : première entrée **0.3.8 / build 25**, identique octet pour octet au flux local signé. Signature Ed25519 du fichier public valide. SHA-256 : `ebd3b0c836568ced04b927929f3e91f4149af7fe2728f693b7f9a9682402441d`. GitHub Pages indique `built` sur le commit attendu. Les utilisateurs peuvent rechercher la mise à jour dans l’application.

Installateur : https://github.com/k2r59/EsaySoft/releases/download/easypaste-v0.3.8/EasyPaste-0.3.8-universal.dmg

## 23. Enregistrement sans remplacement — chantier local du 28 octobre 2026

Nouvelle consigne d’Hervé : **toute modification de contenu enregistrée dans EasyPaste doit créer une nouvelle entrée ; ne jamais remplacer l’original**. Cette règle remplace l’ancienne demande d’annotation avec remplacement. Retirer les choix « Créer une copie » et « Remplacer l’original » : un bouton Enregistrer suffit. Aucune nouvelle publication n’est demandée après 0.3.8.

- Éditeur structuré (JSON, SQL, CSV, XML, Markdown, SVG) : Enregistrer directement, raccourci ⌘S, Exporter séparé. Suppression du menu de choix et de la confirmation de remplacement. L’onglet Original continue à montrer la source après enregistrement.
- Éditeur de texte classique : enregistrement asynchrone d’une variante, avec RTF, lien de parenté, origine web et collections. Désactivation pendant l’écriture, fermeture uniquement après réussite, erreur visible sans perdre le texte.
- Annotation : bouton Terminé et ⌘S passent uniquement par `saveImage(parent:)`, option de remplacement non exposée. Le contrôleur ne possède plus de branche de remplacement et `History.replaceImage` est supprimée. Les fichiers d’annotation partagés avec EasyShoot restent identiques ; EasyShoot n’est pas modifié.
- Stockage : nouvelle identité à chaque enregistrement, y compris si le résultat est identique. `History.edit` est supprimée ; `saveEditedText` crée une variante chiffrée et laisse le fichier source intact. La création d’un texte neuf contourne aussi la déduplication de l’import du presse-papiers. Les favoris, collections et suppressions restent des actions de gestion sur la carte existante ; la collecte ordinaire conserve sa déduplication.
- Compteur : chaque variante commence à zéro, celui de l’original reste intact. Limites de taille et validation des images conservées. Aucun réencodage supplémentaire des PNG.
- Tests : 308 en Debug sans échec (42,65 s), 308 en Release sans échec (39,88 s). Quatre nouveaux tests couvrent les six formats, les répétitions identiques, le texte enrichi/liens/couleurs, l’origine et les collections, les compteurs, les nouveaux extraits identiques et un échec d’enregistrement. Ils comparent aussi les octets du fichier source chiffré avant/après. Les anciens tests de remplacement sont adaptés à la conservation de l’original et aux modifications concurrentes de métadonnées.
- Rendus natifs générés dans `/Users/k2r59/Library/Caches/EasyPaste-visual-review/copy-only`, Markdown inspecté : les trois actions Exporter / Enregistrer / Copier sont lisibles et tiennent dans la fenêtre.

### Installation locale

Compilation universelle réussie (arm64 et x86_64). Bundle privé 0.3.8 (25) signé dans `/Users/k2r59/Library/Caches/EasyPaste-local-install/copy-only/EasyPaste.app`, installé au chemin habituel après fermeture normale depuis le menu. Sauvegarde précédente : `before-copy-only.zip` dans ce même dossier. Signature stricte vérifiée avant et après remplacement ; SHA-256 du binaire installé : `f4d9a7e3a34d81a38785fad3b5758463090695a09a4149bbe73032bd87d88be6`. Aucun changement de permissions, aucun historique utilisateur modifié pour ces essais.

Relancement réel vérifié : barre rapide ouverte et recherche focalisée. L’aperçu du changelog s’ouvre. La tentative suivante d’ouverture de Formater via l’outil CUA renvoie AXError.failure, puis aucune fenêtre accessible ; le processus EasyPaste reste vivant et aucun rapport de crash EasyPaste n’est trouvé. Cette dernière étape ne constitue donc pas une validation manuelle de l’éditeur installé. Les rendus natifs, les tests d’intégration et la correspondance du binaire installé sont validés. Aucun enregistrement d’une copie de test dans l’historique utilisateur n’a été effectué.

Aucune release, aucun tag et aucun flux OTA modifiés après la publication 0.3.8 : cette évolution reste locale et dans les sources de la branche. Ne pas confondre le paquet public 0.3.8 avec ce binaire privé, qui affiche le même numéro mais ajoute l’enregistrement sans remplacement.

## 24. Options vidéo visuellement grisées — 28 octobre 2026, chantier local

Hervé signale que les interrupteurs Microphone / Webcam / Son de l’ordinateur paraissent tous grisés et non activables. Lecture réelle du panneau : les trois commutateurs sont exposés comme disponibles ; l’action Accessibilité sur Microphone passe bien de off à on et affiche le choix de source. Pourtant, même sur on, le rendu reste gris. Le test de clic par coordonnées échoue côté CUA avec `noWindowsAvailable` ; ne pas le présenter comme preuve d’un clic physique ignoré par l’application.

`PreferenceToggle` imbriquait un `Toggle` natif avec `.allowsHitTesting(false)` dans un bouton couvrant la ligne. Le rendu natif donnait une fausse impression de contrôle désactivé. Remplacement du contrôle décoratif par une piste et un curseur SwiftUI : couleur du thème sur on, position gauche/droite distincte, un seul bouton pour toute la ligne. Sémantique Accessibilité de commutateur conservée, état désactivé du parent respecté par le style, animation courte supprimée si Réduire les animations est actif. Le composant étant partagé, les réglages bénéficient également du correctif.

Test de rendu dédié : état on coloré même dans une fenêtre inactive, thèmes clair et sombre, absence de NSSwitch natif imbriqué susceptible d’intercepter les clics. Les quatre tests de disposition passent aussi. Une tentative de test Accessibilité interne avec NSHostingView n’exposait aucun enfant AX dans ce banc de test : elle a été remplacée par le test de rendu, sans revendiquer de validation automatisée des actions AX. L’action AX a bien fonctionné dans l’application réelle avant correction.

Aucune permission caméra/micro supplémentaire accordée et aucun enregistrement lancé. Le panneau de test a été annulé, ce qui remet ses options locales à zéro à la prochaine ouverture. Aucune publication demandée pour ce correctif.

Vérification réelle après première installation du correctif : les trois options Microphone, Webcam et Son de l’ordinateur passent successivement à on via leurs actions Accessibilité. Le panneau affiche trois pistes bleues, avec les sources micro et caméra disponibles. Annulation sans démarrage de vidéo. Le clic par coordonnées de CUA ne constitue toujours pas une validation fiable du périphérique physique.

Complément : le contour décoratif du modificateur `Surface` est explicitement exclu de la réception des clics et de l’arbre Accessibilité. Il ne doit jamais pouvoir intercepter les interactions avec les contrôles contenus dans le panneau. Le test de rendu du commutateur utilise aussi ce panneau de production.

Validation finale : **309 tests Release, zéro échec, 39,61 s**, puis compilation universelle arm64/x86_64. Installation signée au chemin habituel, SHA-256 du binaire : `7193b05250419e9127394705752361d4b5fc5dcf753c482eaf954943097dcb05`. Bundle de préparation dans `/Users/k2r59/Library/Caches/EasyPaste-local-install/switches/EasyPaste.app`, sauvegarde de la version précédente dans `before-switches.zip`. Version privée toujours 0.3.8 (25), incluant aussi les enregistrements sans remplacement de la section 23.

Après le dernier relancement, les six transitions réelles via actions Accessibilité ont réussi : Microphone on/off, Webcam on/off, Son de l’ordinateur on/off. Panneau vidéo laissé ouvert avec les trois options sur off, pour l’essai de l’utilisateur. Aucun enregistrement lancé, aucune permission modifiée, aucune publication OTA.
