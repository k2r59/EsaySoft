# EasyPaste · Web

Extension Chrome locale, en français, sous licence MIT. Elle complète EasyPaste sans compte, serveur ni connexion native entre le navigateur et l’app. Elle fonctionne aussi seule : tout passe par le presse-papiers du système.

## Installer pour essayer

1. Ouvrir `chrome://extensions` dans Chrome.
2. Activer **Mode développeur**.
3. Cliquer sur **Charger l’extension non empaquetée** et choisir ce dossier `BrowserExtension`, celui qui contient `manifest.json`.
4. Dans le menu Extensions de Chrome, épingler **EasyPaste · Web**.

Aucune publication sur le Chrome Web Store n’a été faite. Pour installer depuis un ZIP, le décompresser d’abord, puis sélectionner son dossier. Pour une mise à jour locale, remplacer les fichiers et utiliser **Actualiser** sur la fiche de l’extension. Aucun système de mise à jour automatique n’est configuré.

## Copier une page

Cliquer sur l’icône EasyPaste, puis **Copier avec la mise en forme**. Une sélection de texte existante est proposée en priorité. Sinon, l’extension récupère le premier article, la zone principale ou, à défaut, le corps de la page.

La copie contient simultanément du **HTML nettoyé** et du **texte brut** : titres, emphases, couleurs de texte et de fond, tailles raisonnables, listes, liens, blocs de code et tableaux. L’application dans laquelle on colle choisit le format qu’elle sait lire. La reproduction n’est pas une capture à l’identique de la mise en page : les grilles complexes, polices téléchargées, scripts et interactions sont retirés.

Le lien visible de la source peut être ajouté ou omis. Le HTML copié contient aussi une métadonnée discrète `easypaste-source-url`, issue de l’adresse de la page ouverte, pour qu’EasyPaste puisse proposer de revenir à l’origine. Elle n’ajoute aucun texte visible et ne modifie pas le texte brut. Seules les adresses HTTP(S) sans identifiant ni mot de passe sont retenues. Les images distantes ne sont pas chargées ou incorporées ; leur texte alternatif est conservé lorsqu’il existe. Les champs de saisie, éléments masqués, contenus intégrés, SVG, formulaires et lecteurs vidéo sont exclus. Les pages internes de Chrome, le Chrome Web Store, certains PDF et les cadres d’un autre domaine ne sont pas accessibles.

Si l’historique d’EasyPaste est activé, l’app récupère cette copie comme n’importe quelle copie habituelle. L’extension n’accorde aucune nouvelle autorisation à l’app macOS.

## Copier les sous-titres YouTube

Sur une page vidéo YouTube, une carte **Sous-titres YouTube** apparaît. **Transcription YouTube**, sélectionnée par défaut, ouvre le panneau natif à votre clic puis récupère les passages affichés. Le panneau est parcouru si YouTube charge ses lignes au défilement ; sa position initiale est ensuite rétablie. La copie propose le texte brut et une version HTML simple avec sa métadonnée d’origine, avec des repères temporels facultatifs. Garder le popup ouvert pendant la préparation.

La langue est celle du panneau YouTube. Pour la changer, utiliser le sélecteur de langue de ce panneau avant de copier. Une recherche active dans la transcription doit être effacée pour éviter une copie limitée aux résultats.

Les pistes directes exposées par le lecteur restent proposées avec leur langue et la mention **auto**. Certaines renvoient une réponse vide alors que la transcription native fonctionne. Quand il n’existe qu’une piste, EasyPaste essaie alors le panneau natif ; avec plusieurs langues, il invite à sélectionner **Transcription YouTube** pour éviter de copier une autre langue sans prévenir.

L’extension ne transcrit pas l’audio, ne fabrique pas de traduction et ne récupère pas de vidéo. Elle ne contourne aucun refus d’accès. Une transcription absente, inaccessible ou qui ne se charge pas produit une erreur et laisse le presse-papiers intact. Les mécanismes du lecteur et la structure du panneau YouTube ne sont pas une API publique stable : cette fonction peut nécessiter une adaptation quand YouTube change son interface.

## Confidentialité et sécurité

- **`activeTab`** : accès temporaire à l’onglet lorsque l’utilisateur ouvre l’extension.
- **`scripting`** : extraction déclenchée dans cet onglet, sans script installé sur tous les sites.
- **`clipboardWrite`** : copie explicite dans le presse-papiers. L’extension ne lit pas son contenu.

Pas de permission globale sur les sites, de cookies via l’API Chrome, de lecture de l’historique, de stockage, de télémétrie, de worker permanent ou de service distant. Les demandes de sous-titres réutilisent uniquement l’URL HTTPS exacte exposée par le lecteur pour la vidéo courante, sur la même origine YouTube et le chemin `/api/timedtext`, avec les accès de la session ouverte. Les redirections et les domaines tiers sont refusés. Aucune clé API ni secret n’est demandé ou conservé.

Le HTML est **reconstruit** avec une liste blanche de balises et de propriétés CSS. Les attributs d’événement, scripts, styles arbitraires, URL `javascript:`, ressources distantes, SVG, MathML, cadres et objets ne sont jamais recopiés. Aucun HTML de la page n’est injecté dans le popup. Le popup a une CSP locale sans connexion réseau et sans code distant.

Les limites sont de 500 000 caractères, 2 Mo de HTML encodé en UTF-8, 8 000 nœuds, 2 000 éléments stylés et 60 niveaux d’imbrication. En cas de dépassement, l’utilisateur est invité à sélectionner un passage plus court : le presse-papiers n’est pas remplacé par un extrait tronqué. Le parcours laisse régulièrement la main au navigateur. Sous-titres : 2 Mo de réponse, 12 000 segments, 500 000 caractères, délai réseau de 10 secondes, lecture du panneau natif limitée à 12 secondes. Aucune surveillance des pages ni tâche automatique en arrière-plan ; une extraction déjà déclenchée peut terminer son parcours après la fermeture du popup.

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

Les tests couvrent la sélection exacte, la mise en forme, les injections HTML/CSS/URL, les éléments masqués, les budgets, les rendus intermédiaires, les réponses YouTube XML/JSON3 malformées, les vidéos changées par navigation interne, les domaines usurpés, les refus/erreurs réseau et l’écriture simultanée HTML + texte. Ils ne remplacent pas une vérification réelle de Chrome et de YouTube ; voir [QA.md](QA.md).

## Références

- [Chrome : accès temporaire à l’onglet actif](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab).
- [Chrome : injection de scripts Manifest V3](https://developer.chrome.com/docs/extensions/reference/api/scripting).
- [Chrome : permissions du presse-papiers](https://developer.chrome.com/docs/extensions/reference/permissions-list).
- [YouTube : afficher une transcription](https://support.google.com/youtube/answer/15930243?hl=fr).
- [YouTube Data API : téléchargement de sous-titres](https://developers.google.com/youtube/data/reference/rest/v3/captions/download). Cette API exige le droit de modifier la vidéo et n’est pas utilisée par l’extension.

Le code est sous [licence MIT](LICENSE). Les droits sur le contenu copié restent ceux de son auteur.
