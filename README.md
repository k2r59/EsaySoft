# EsaySoft

Trois applications macOS natives, en français, gratuites et sous licence MIT.
Cette première distribution fonctionne en local, sans compte EsaySoft ni synchronisation iCloud.

| Application | Usage | Sources et guide |
| --- | --- | --- |
| **EasyShoot** | Capturer l’écran, extraire du texte, annoter des images et monter une vidéo. | [app/EasyShoot](app/EasyShoot) |
| **EasyTile** | Placer les fenêtres avec une palette, des raccourcis ou un menu pendant leur déplacement. | [app/EasyTile](app/EasyTile) |
| **EasyPaste** | Retrouver ses copies, organiser ses favoris et capturer des images, du texte ou des vidéos dans le presse-papiers. | [app/EasyPaste](app/EasyPaste) |

## Compatibilité

Les trois applications nécessitent **macOS 15 ou ultérieur**. Les scripts produisent des applications universelles pour Apple Silicon et Intel. Les essais manuels ont été réalisés sur un Mac Apple Silicon ; l’exécution sur un Mac Intel reste à vérifier.

## Compiler une application

Installer Xcode et ses outils de développement, avec Swift 6 et le SDK macOS. Aucune dépendance Swift externe n’est nécessaire.

Depuis la racine du dépôt, par exemple pour EasyPaste :

```sh
cd app/EasyPaste
./scripts/build.sh
open dist/EasyPaste.app
```

Utiliser `app/EasyShoot` ou `app/EasyTile` pour les deux autres applications. Chaque dossier contient son guide, ses sources et ses scripts de distribution.

La compilation sans identité Developer ID utilise une signature locale pour les essais. Pour fabriquer un DMG signé et notarisé, configurer son certificat Developer ID Application et son profil de notarisation dans le trousseau, puis lancer dans le dossier de l’application :

```sh
CODE_SIGN_IDENTITY='Developer ID Application: Votre équipe (TEAMID)' \
NOTARY_PROFILE='VotreProfilDansLeTrousseau' \
./scripts/package.sh
```

Le dossier `dist/` contient alors le DMG, le ZIP de l’application, l’archive des sources et les empreintes SHA-256. Ouvrir le DMG, glisser l’application dans Applications et la lancer depuis ce dossier.

## Autorisations et données

- **EasyShoot** demande l’accès à l’écran pour les captures et l’enregistrement vidéo. Ses captures restent sur le Mac.
- **EasyTile** demande l’Accessibilité pour déplacer les fenêtres des autres applications.
- **EasyPaste** conserve l’historique chiffré localement. L’accès à l’écran sert aux captures et aux vidéos ; le microphone est facultatif. L’Accessibilité permet le collage direct. Sans elle, la copie fonctionne avec un collage manuel par Commande + V.

Les connecteurs MCP d’EasyShoot et d’EasyPaste sont documentés dans leurs guides. EasyPaste limite son connecteur, désactivé par défaut, aux collections explicitement autorisées.

Les certificats, clés privées, identifiants Apple, historiques personnels et fichiers des essais manuels ne font pas partie du dépôt. Les limitations fonctionnelles et les commandes de test figurent dans le guide de chaque application.

## Licence

Le code et les ressources originales de ce dépôt sont publiés sous [licence MIT](LICENSE). Chaque application conserve également sa licence et ses mentions d’attribution dans son propre dossier.

La licence permet l’utilisation, la modification et la redistribution, y compris commerciale, en conservant les mentions requises. Les marques de tiers citées dans les guides appartiennent à leurs propriétaires respectifs.
