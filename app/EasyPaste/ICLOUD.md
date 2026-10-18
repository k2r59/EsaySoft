# Synchronisation iCloud d’EasyPaste

La branche 0.3.0 ajoute une synchronisation facultative de l’historique avec CloudKit. La version publique 0.2.1 reste locale. **La connexion au service Apple n’est pas encore validée : le compte Xcode a refusé la création du conteneur faute de droits.**

## Ce qui se synchronise

Textes et leurs formats, liens, couleurs, images originales, captures annotées, vidéos, titres, OCR, favoris, collections et corbeille sont synchronisés dans la base privée du compte Apple connecté au Mac. Une image n’est pas recompressée ; une vidéo conserve ses octets d’origine. Les références de fichiers Finder restent locales : elles ne constituent pas une sauvegarde des fichiers.

La synchronisation est désactivée par défaut. Son activation affiche le contenu envoyé, la destination et l’effet des suppressions. Un changement de compte Apple arrête la synchronisation ; une nouvelle activation est nécessaire pour envoyer les copies locales au nouveau compte. La désactivation conserve les copies locales et celles déjà présentes dans iCloud.

Les exclusions, les raccourcis, les autorisations MCP et les autres réglages de chaque Mac restent locaux. Recevoir une collection ne donne aucun accès à un assistant. La durée de conservation reste propre à chaque Mac ; l’expiration supprime aussi la copie synchronisée. Utiliser la même durée sur les Macs pour éviter qu’un délai plus court efface les copies conservées plus longtemps ailleurs. Favoris et collections restent exemptés de l’expiration.

## Configuration Apple à terminer

L’équipe de distribution est **Les papas du code**, `WN9MHL56A9`. Un membre autorisé à gérer les identifiants et les conteneurs doit effectuer les étapes suivantes dans [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).

1. Vérifier l’identifiant explicite macOS `app.easypaste.mac`.
2. Activer iCloud avec CloudKit et lui associer le conteneur `iCloud.app.easypaste.mac`. Activer aussi Push Notifications : `CKSyncEngine` utilise des notifications silencieuses pour recevoir les changements.
3. Générer le profil de développement Mac pour cet identifiant et ce Mac. Le projet Xcode peut ensuite récupérer le profil automatiquement.
4. Tester le service dans l’environnement Development avec des données fictives et deux historiques isolés. Le mode `--demo` désactive volontairement CloudKit et ne sert pas à cette validation réseau.
5. Dans [CloudKit Console](https://icloud.developer.apple.com/), vérifier puis déployer le schéma en Production. L’application utilise une zone privée `EasyPasteHistory`, un type `EasyPasteItem`, les champs chiffrés `header` (Data) et `movieFingerprint` (String), et les assets `content` (JSON) et `movie` (vidéo). Aucun champ de contenu utilisateur ne doit être ajouté à la base publique.
6. Créer un profil de distribution **Developer ID** pour cet App ID, associé au certificat Developer ID Application utilisé pour la signature. Télécharger le profil `.provisionprofile` ; il ne doit pas être commité.
7. Construire, signer et notariser le DMG avec ce profil. Tester ensuite le binaire de distribution en Production avant publication.

Xcode a renvoyé le 18 octobre 2026 : `Your account does not have sufficient permissions to modify containers.` L’existence du certificat Developer ID ne suffit donc pas à terminer la configuration iCloud avec le compte actuellement connecté.

Pour générer le projet de configuration, avec XcodeGen installé :

```sh
xcodegen generate
open EasyPaste.xcodeproj
```

Le projet utilise le SDK macOS, macOS 15 minimum, Swift 5 et la signature automatique. Les fichiers Xcode générés et les profils personnels restent exclus de Git. Pour une autre équipe ou un fork, adapter les identifiants dans `CloudConfiguration`, `Configuration`, `project.yml` et le validateur de signature.

Pour construire une distribution iCloud après configuration Apple :

```sh
CLOUD_PROFILE='/chemin/EasyPaste-DeveloperID.provisionprofile' \
CODE_SIGN_IDENTITY='Developer ID Application: Les papas du code (WN9MHL56A9)' \
NOTARY_PROFILE='EasyShoot' \
./scripts/package.sh
```

Le script valide l’équipe, l’App ID exact, le conteneur, l’environnement Production, l’expiration et le certificat autorisé avant la compilation. Il embarque le profil dans `Contents/embedded.provisionprofile` avant de signer. Sans `CLOUD_PROFILE`, le script construit une version locale dont le bouton iCloud est désactivé ; elle reste utilisable sans compte Apple Developer.

## Fonctionnement et reprise

`CKSyncEngine` gère les notifications, les reprises réseau et les limitations du service. Le contenu est préparé hors du fil de l’interface, deux enregistrements au maximum par lot. Les vidéos sont déchiffrées et rechiffrées par blocs de 1 Mo ; les modifications d’un titre ou d’un favori ne réécrivent pas la vidéo locale. L’inventaire initial retrouve les modifications locales intervenues pendant que l’app était fermée.

Les copies locales restent chiffrées avec une clé propre au Mac, stockée dans le trousseau. Les assets CloudKit bénéficient de la protection Apple ; les champs de métadonnées du protocole utilisent `encryptedValues`. Cela ne constitue pas une promesse de chiffrement de bout en bout dans toutes les configurations de compte. Aucun mot de passe Apple ni clé du trousseau local n’est envoyé par le code de synchronisation.

CloudKit reçoit des fichiers temporaires déchiffrés dans `Vault/CloudTransfers`, dossier accessible uniquement à l’utilisateur (0700, fichiers 0600). Ils sont retirés après le transfert, à l’arrêt de la synchronisation ou au prochain lancement. Les reprises d’état et les suppressions sont conservées dans des fichiers chiffrés du coffre.

Chaque élément possède une révision avec date et identifiant de départage. En cas de modification simultanée, la révision la plus récente l’emporte ; il n’y a pas de fusion des paragraphes. La révision progresse localement même si l’horloge recule. Une suppression définitive conserve une petite marque de suppression chiffrée : un Mac hors ligne ne peut pas réintroduire l’ancien élément. Ces marques ne contiennent pas le contenu supprimé et ne sont pas purgées automatiquement.

Une erreur de format ou d’import interrompt la synchronisation avant de poursuivre le suivi des changements. Une erreur d’envoi ne suffit jamais à supprimer une copie locale. La suppression de la zone iCloud et le changement de compte arrêtent le service au lieu de réenvoyer silencieusement tout l’historique.

## Validation avant diffusion

Les tests locaux simulent deux coffres indépendants, avec deux clés de chiffrement. Ils vérifient la convergence, la suppression hors ligne, la corbeille, les collections, les autorisations MCP locales, les données invalides, les fichiers historiques, l’isolation des transferts et les octets vidéo.

Ils ne remplacent pas les essais CloudKit réels. Avant diffusion, vérifier sur deux clients : premier envoi et récupération, réception automatique, arrêt et reprise hors connexion, conflit de modification, suppression et expiration, manque de place, changement de compte, interruption de transfert, récupération après relancement, puis la même séquence avec le DMG signé dans l’environnement Production. Ne pas activer la collecte de données personnelles dans les clients de validation.

Références Apple : [Developer ID et CloudKit](https://developer.apple.com/developer-id/), [signature de distribution macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9), [champs chiffrés](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues).
