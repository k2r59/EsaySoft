# EsaySoft

Trois applications macOS natives, en français, gratuites et sous licence MIT.
L’historique fonctionne en local, sans compte EsaySoft ni synchronisation iCloud.
EasyPaste propose aussi un partage Bitwarden facultatif, désactivé par défaut ;
seuls les éléments choisis sont transmis après activation et connexion.

| Application | Usage | Sources et guide |
| --- | --- | --- |
| **EasyShoot** | Capturer l’écran, extraire du texte, annoter des images et monter une vidéo. | [app/EasyShoot](app/EasyShoot) |
| **EasyTile** | Placer les fenêtres avec une palette, des raccourcis ou un menu pendant leur déplacement. | [app/EasyTile](app/EasyTile) |
| **EasyPaste** | Retrouver ses copies, organiser ses favoris et capturer des images, du texte ou des vidéos dans le presse-papiers. | [app/EasyPaste](app/EasyPaste) |

## Télécharger et installer

Les installateurs de la [distribution locale du 17 octobre 2026](https://github.com/k2r59/EsaySoft/releases/tag/local-2026-10-17) sont signés avec Developer ID et notarisés par Apple :

- [EasyShoot 0.2.2 — télécharger le DMG](https://github.com/k2r59/EsaySoft/releases/download/local-2026-10-17/EasyShoot-0.2.2-universal.dmg)
- [EasyTile 1.1.0 — télécharger le DMG](https://github.com/k2r59/EsaySoft/releases/download/local-2026-10-17/EasyTile-1.1.0-universal.dmg)
- [EasyPaste 0.2.8 — télécharger le DMG](https://github.com/k2r59/EsaySoft/releases/download/easypaste-v0.2.8/EasyPaste-0.2.8-universal.dmg)

Ouvrir le DMG, glisser l’application dans **Applications**, puis l’ouvrir depuis ce dossier. Autoriser les fonctions souhaitées lorsque macOS le demande. Aucun compte développeur ni Xcode n’est nécessaire pour utiliser ces installateurs.

La release contient les empreintes `SHA256SUMS` et la licence MIT. Les archives « Source code » contiennent les projets à compiler, tandis que les fichiers `.dmg` contiennent les applications à installer.

## Compatibilité

Les trois applications nécessitent **macOS 15 ou ultérieur**. Les scripts produisent des applications universelles pour Apple Silicon et Intel. Les essais manuels ont été réalisés sur un Mac Apple Silicon ; l’exécution sur un Mac Intel reste à vérifier.

## Compiler une application

Installer Xcode et ses outils de développement, avec Swift 6 et le SDK macOS. Aucune dépendance Swift externe n’est nécessaire.
EasyPaste embarque l’implémentation C d’Argon2 sous CC0 pour les comptes Bitwarden concernés ;
voir ses [mentions des composants tiers](app/EasyPaste/THIRD-PARTY-NOTICES.md).

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

## Développement en cours

La branche `main` contient les versions locales distribuées. Le [rapport de validation d’EasyPaste 0.2.8](app/EasyPaste/QA-0.2.8.md) détaille les contrôles du rendu SVG et de la pipette. Les tests Markdown, JSON, SQL, CSV et XML restent inclus.

Le code de synchronisation iCloud d’EasyPaste 0.3.0 est disponible sur la branche [codex/easypaste-icloud](https://github.com/k2r59/EsaySoft/tree/codex/easypaste-icloud). La configuration Apple et les essais CloudKit entre deux Macs restent à terminer. Cette version en développement n’est pas incluse dans les installateurs publics.

## Licence et attributions

Le code et les ressources originales de ce dépôt sont publiés sous [licence MIT](LICENSE). Chaque application conserve également sa licence et ses mentions d’attribution dans son propre dossier.

La [licence MIT](https://opensource.org/license/mit) permet l’utilisation, la modification et la redistribution, y compris commerciale, en conservant les mentions de copyright et le texte de la licence. Les scripts de distribution d’EasyPaste et d’EasyTile conservent l’attribution à EasyShoot dont ils sont adaptés. Les scripts incluent la licence de chaque application dans son paquet, son DMG et son archive de sources.

Les icônes des applications sont dessinées par les scripts `generate-icon.swift`. L’illustration d’EasyPaste a été créée avec imagegen ; sa provenance et son prompt figurent dans [ASSET-PROMPT.txt](app/EasyPaste/ASSET-PROMPT.txt). Aucun paquet Swift externe n’est embarqué. Les composants système Apple appelés par les applications et les marques citées dans les guides ne sont pas placés sous la licence MIT du projet.
