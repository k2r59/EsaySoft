# EasyPaste

Un gestionnaire de presse-papiers natif pour macOS, gratuit et sous licence MIT. Interface en français, couleurs graphite, menthe et lavande. SwiftUI pour l’interface, AppKit pour le presse-papiers et les fenêtres.

## Installation

1. Ouvrir `dist/EasyPaste-0.2.2-universal.dmg`.
2. Glisser EasyPaste dans Applications, puis l’ouvrir.
3. Cliquer sur **Activer mon historique**. Les prochaines copies seront enregistrées.
4. Depuis une autre application, ouvrir la barre rapide avec **Maj + Commande + V**.
5. Choisir une carte, puis appuyer sur **Entrée**. Pour le collage direct, autoriser EasyPaste dans **Réglages → Coller sans détour**. Sans cette autorisation, la sélection est copiée et peut être collée avec **Commande + V**.

macOS 15 ou ultérieur. L’installateur universel contient les exécutables Apple Silicon et Intel. La fermeture de la bibliothèque laisse l’app disponible dans la barre des menus. Utiliser **Quitter EasyPaste** pour l’arrêter.

## Fonctions disponibles

- Historique de textes, liens, couleurs, images, vidéos enregistrées et références de fichiers. Déduplication des copies identiques.
- Barre rapide centrée au bas de l’écran actif et bibliothèque avec vues détaillée et compacte.
- Recherche par mots, sans distinction d’accents, dans le texte, les titres, les applications sources et le texte reconnu dans les images. Filtres par type, application, collection et date du jour.
- Favoris et collections permanentes. Suppression au choix, individuelle ou multiple, avec bouton Annuler et restauration depuis la corbeille pendant 7 jours. Suppression définitive possible pour les seuls éléments choisis, après confirmation. Les fichiers d’origine restent intacts.
- Sélection multiple avec Commande ou Maj. Plusieurs textes sont regroupés avec des sauts de ligne ; plusieurs fichiers ou images conservent leurs éléments de presse-papiers.
- Copier, coller directement, coller en texte brut et glisser-déposer. Le glissement d’une carte regroupant plusieurs fichiers porte sur le premier fichier ; la copie conserve l’ensemble.
- Éditeur de texte enrichi avec gras, italique, souligné, barré et annulation native pendant l’édition. Création de textes favoris.
- Aperçu des images et du texte, Quick Look des fichiers, ouverture des liens dans le navigateur par défaut.
- Reconnaissance de texte locale avec Vision, en français et en anglais. Le texte reconnu devient recherchable et copiable.
- Pile de collage : collecte ordonnée, retrait des doublons, inversion et copie du prochain élément. Le raccourci de pile prépare le prochain élément ; Commande + V le colle. EasyPaste n’intercepte pas chaque Commande + V.
- Collecte en pause, exclusions d’applications, durée de conservation et ouverture à la connexion.
- Connecteur MCP local, désactivé par défaut, limité aux collections explicitement autorisées.

## Capturer et annoter

Le menu près de l’heure propose **Capturer une zone** directement. Le sous-menu **Capture** donne accès aux fenêtres, à l’écran entier, à l’OCR et à la vidéo. Le bouton **Capturer** reste disponible dans la bibliothèque et la barre rapide.

1. Choisir **Capturer une zone**, puis tracer un rectangle à la souris. Appuyer sur **Échap** pour annuler.
2. Retrouver la capture dans la barre rapide. L’image est aussi copiée, prête à coller avec **Commande + V**.
3. Survoler sa carte et cliquer sur le crayon pour ouvrir l’éditeur.
4. Ajouter une flèche, un cadre, du texte ou un surlignage. **Masquer** recouvre les informations avec un rectangle opaque. **Recadrer** conserve la zone choisie.
5. Cliquer sur **Créer une copie**. La version modifiée apparaît à côté de l’original et remplace le contenu du presse-papiers. L’original reste intact.

Les captures sont enregistrées en PNG sans perte, à la densité native de l’écran. Une zone de 600 × 400 points sur un écran Retina produit 1 200 × 800 pixels. Les miniatures servent à l’affichage ; la copie conserve tous les pixels de l’original. Dans **Aperçu**, **100 %** affiche un pixel de l’image pour un pixel de l’écran, avec défilement si nécessaire. **Ajuster** montre l’ensemble sans agrandir artificiellement une petite image. Les images sont limitées à 50 mégapixels et à 20 Mo encodés.

Pour extraire du texte visible, choisir **Extraire le texte d’une zone**, puis encadrer les lignes voulues. Le texte reconnu est enregistré et copié. La reconnaissance utilise Vision sur le Mac.

## Enregistrer une vidéo

1. Choisir **Capturer → Enregistrer une vidéo…**.
2. Choisir une zone ou l’écran entier, puis activer le son de l’ordinateur et le microphone selon le besoin.
3. Cliquer sur **Continuer**. Pour une zone, tracer le rectangle. Le décompte dure trois secondes.
4. Cliquer sur le bouton rouge près de l’heure pour arrêter. Le menu **Capturer** propose aussi **Arrêter l’enregistrement**.
5. Ouvrir la carte vidéo pour la lire, la copier ou choisir **Enregistrer…** afin d’exporter le fichier MP4.

La vidéo utilise H.264 à 30 images/s au maximum. Le grand côté est limité à 1 920 pixels, ou à 3 840 pixels avec **Haute définition · jusqu’à 4K**. Les proportions de la zone sont conservées. La sélection doit tenir sur un seul écran. Prévoir au moins 1,5 Go d’espace libre ; l’enregistrement s’arrête automatiquement vers 800 Mo et l’import accepte jusqu’à 1 Go.

La copie vidéo fournit un fichier MP4 aux applications compatibles. Le collage dans un champ de texte simple ne peut pas y insérer une vidéo. Cette version ne comporte pas d’éditeur de montage vidéo.

macOS demande l’autorisation d’enregistrer l’écran à la première capture. Le microphone possède une autorisation distincte, demandée uniquement lorsque cette option est choisie. Si macOS exige de quitter l’app, la rouvrir depuis Applications.

## Raccourcis

| Action | Raccourci |
| --- | --- |
| Ouvrir la barre rapide | Maj + Commande + V |
| Naviguer dans la barre | Flèche gauche / droite |
| Coller la sélection | Entrée |
| Coller en texte brut | Maj + Entrée |
| Coller une des neuf premières cartes | Commande + 1 à 9 |
| Collage rapide en texte brut | Maj + Commande + 1 à 9 |
| Rechercher | Commande + F |
| Modifier un texte ou annoter une image | Commande + E |
| Capturer une zone | Contrôle + Option + Commande + C |
| Extraire le texte d’une zone | Contrôle + Option + Commande + X |
| Aperçu | Commande + Y |
| Ouvrir un lien ou fichier | Commande + O |
| Créer un texte | Commande + N |
| Créer une collection | Maj + Commande + N |
| Pause / reprise dans EasyPaste | Commande + T |
| Préparer l’élément suivant de la pile | Contrôle + Option + Commande + V |
| Supprimer les cartes sélectionnées (hors champ de texte) | Retour arrière |
| Annuler la dernière suppression (hors champ de texte) | Commande + Z |
| Fermer la barre | Échap |

Les numéros de collage rapide utilisent les touches physiques de la rangée numérique, y compris sur un clavier AZERTY. Les raccourcis globaux sont fixes dans cette version. En cas de conflit avec une autre application, ouvrir la barre depuis le menu EasyPaste.

## Données et confidentialité

La collecte est désactivée au premier lancement. Elle observe les changements du presse-papiers toutes les 650 ms lorsqu’elle est active ; des copies extrêmement rapprochées peuvent donc ne pas toutes être conservées.

Les enregistrements sont chiffrés individuellement avec AES-GCM dans `~/Library/Application Support/EasyPaste/Vault`. La clé est conservée dans le trousseau macOS, accessible sur ce Mac uniquement. Les écritures sont atomiques ; le répertoire utilise les droits 0700 et les fichiers 0600. Une erreur de chiffrement ou d’écriture met la collecte en pause et affiche un message.

Les vidéos sont chiffrées par blocs de 1 Mo, sans charger le fichier entier en mémoire. La lecture et la copie créent un fichier temporaire déchiffré, accessible uniquement à l’utilisateur. Les copies temporaires de plus de 24 heures sont supprimées au lancement suivant. Un enregistrement en cours reste dans `~/Library/Application Support/EasyPaste/Recordings` ; il est supprimé après son import chiffré. En cas d’échec, ce fichier permet une récupération.

Les types de presse-papiers marqués confidentiels, temporaires ou générés automatiquement sont ignorés. Plusieurs gestionnaires de mots de passe sont exclus par défaut. Une extension de navigateur qui ne marque pas un secret peut cependant le laisser enregistrer : utiliser la pause ou exclure le navigateur dans ce cas.

L’app ne transmet aucune copie à un serveur. Elle ne télécharge pas d’aperçus de liens. L’ouverture volontaire d’un lien utilise le navigateur de l’utilisateur. Les références de fichiers pointent vers leur emplacement original ; EasyPaste ne sauvegarde pas leur contenu.

La conservation est de 30 jours par défaut, réglable à 1 jour, 7 jours, 1 an ou toujours. Favoris et collections sont exemptés. Au-delà de 1 Go de contenu original, la collecte se met en pause ; une copie est limitée à 20 Mo. Le chiffrement et l’encodage ajoutent de l’espace disque. Conserver une sauvegarde du Mac incluant les données et le trousseau : cette version n’offre pas de sauvegarde portable ni de restauration intégrée.

## Connecteur MCP

Installer l’app dans Applications. Dans **Réglages → Un lien avec tes assistants**, activer le connecteur puis autoriser les collections voulues. Copier la configuration depuis ce même écran.

```json
{
  "mcpServers": {
    "easypaste": {
      "command": "/Applications/EasyPaste.app/Contents/MacOS/EasyPaste",
      "args": ["--mcp"]
    }
  }
}
```

Le client MCP lance le processus et communique par entrée/sortie standard. Aucun service réseau ni serveur distant n’est nécessaire. Les outils sont en lecture seule : `list_collections`, `search_clips` et `read_clip`. Ils n’accèdent ni à l’historique privé ni à la corbeille, et ne transmettent pas les données binaires des images ou fichiers. Les textes et chemins présents dans une collection partagée deviennent lisibles par l’assistant connecté. Désactiver le connecteur ou retirer une collection révoque cet accès pour les requêtes suivantes.

## Fluidité

- Lecture initiale et chiffrement hors du fil de l’interface.
- Contenus complets relus à la demande ; seuls textes, métadonnées et miniatures restent dans l’interface.
- Miniatures limitées à 640 pixels et cache d’images plafonné à 32 Mo.
- Aperçu ajusté décodé en arrière-plan selon la densité de l’écran (600 pixels en 1×, 1 200 en 2× au maximum). Le mode 100 % décode l’original à la demande et le libère au retour à Ajuster.
- Recadrage direct des pixels ; conservation du profil couleur RGB pendant l’annotation. Assemblage des captures en arrière-plan, sans interpolation des pixels entre écrans 1× et 2×.
- OCR sérialisé en arrière-plan, avec image de travail réduite à 2600 pixels.
- Recherche différée de 140 ms pendant la frappe, annulable, calculée en arrière-plan.
- Grilles et barre paresseuses ; bibliothèque paginée par groupes de 80 cartes.
- Dates relatives statiques pendant l’affichage, sans actualisation de chaque carte toutes les secondes.

Le test synthétique de recherche sur 10 000 notes prend environ 40 ms sur le Mac de développement en compilation de débogage. Ce chiffre ne mesure pas le temps de chargement d’une photothèque ni les images par seconde de l’interface.

## Développement

Nécessite Xcode avec le SDK macOS et Swift 6. Aucune dépendance externe.

```sh
swift test
./scripts/build.sh
open dist/EasyPaste.app
```

Pour inspecter l’interface avec des données fictives et sans collecter le presse-papiers :

```sh
open -n dist/EasyPaste.app --args --demo
```

Quitter auparavant l’autre instance d’EasyPaste. Le mode démo utilise un dossier temporaire et une clé éphémère, puis supprime ses données à la fermeture normale.

Pour créer un installateur signé et notarisé avec ses propres identifiants :

```sh
CODE_SIGN_IDENTITY='Developer ID Application: Votre équipe (TEAMID)' \
NOTARY_PROFILE='VotreProfilDansLeTrousseau' \
./scripts/package.sh
```

Aucun certificat privé ni identifiant Apple n’est inclus dans le projet. Le script produit le DMG, une archive de l’app, une archive des sources et leurs empreintes SHA-256 dans `dist/`.

## Vérification de la version 0.2

Le 17 octobre 2026, les 26 tests automatisés passent. Ils couvrent le chiffrement, la corruption, les mauvaises clés, les formats, les exclusions, la recherche, l’OCR, la rétention, la suppression et le contrôle d’accès MCP. Les tests ajoutés couvrent les dimensions Retina, les annotations, les copies adjacentes, la sélection, les vidéos chiffrées et un import MP4 réel. Un test reproduit la taille de fichier périmée dans le cache macOS. Le lecteur natif est également instancié trois fois dans le test d’intégration.

Les essais réels de capture comprennent une zone Retina, l’OCR, les annotations et des enregistrements vidéo avec ou sans audio. Le lecteur natif a été rouvert trois fois après correction du retour vers la bibliothèque. L’export MP4 conserve les mêmes octets que le fichier de lecture, sans recompression.

Les contrôles visuels portent sur la bibliothèque, la barre rapide, la recherche sans accents, la sélection, l’édition enrichie, le retour à la ligne et la suppression avec annulation. L’essai utilise un historique fictif distinct des données personnelles. Le collage automatique dans une autre application reste à vérifier après l’autorisation Accessibilité ; le chemin de copie est testé dans un presse-papiers de test isolé.

Le premier appel à Vision peut prendre davantage de temps pendant l’initialisation du moteur Apple. L’interface reste disponible et indique « Lecture du texte… » pendant l’analyse.

## Périmètre de la version 0.2

EasyPaste est une application indépendante, inspirée des usages de Paste, avec son propre code et son propre design. Elle n’intègre pas la synchronisation iCloud, les apps iPhone/iPad, les collections collaboratives, les suggestions Apple Intelligence, un navigateur de liens intégré, la rotation d’images, les raccourcis personnalisables ou le masquage automatique pendant un partage d’écran.

Les pistes fonctionnelles ont été comparées à la documentation officielle de [Paste](https://pasteapp.io/help). Aucun code ni visuel de Paste n’est réutilisé.

## Illustration

L’illustration décorative originale a été créée avec l’outil imagegen intégré. Elle est embarquée dans l’app et décodée une seule fois à une taille limitée. Le fichier source est `Sources/EasyPaste/Resources/clipboard-studio.png` ; le prompt de création figure dans [ASSET-PROMPT.txt](ASSET-PROMPT.txt). Les commandes et les textes restent des composants natifs.

## Licence

[MIT](LICENSE). Gratuit, modifiable et redistribuable selon cette licence. La signature Apple du binaire distribué n’accorde aucun accès aux clés privées de signature.

Les contrôles de netteté, de copie et de réactivité de la version 0.2.2 sont détaillés dans [QA-0.2.2.md](QA-0.2.2.md).
