# EasyTile

EasyTile organise les fenêtres macOS depuis une palette au clavier ou un aperçu de l’écran. Application native AppKit et SwiftUI, sous licence MIT.

## Installer

Compatible avec macOS 15 ou ultérieur, sur Mac Intel et Apple Silicon.

1. Ouvre le fichier DMG.
2. Glisse EasyTile dans Applications.
3. Lance EasyTile depuis Applications.
4. Clique sur **Autoriser EasyTile**, puis active EasyTile dans **Réglages Système → Confidentialité et sécurité → Accessibilité**.
5. Reviens dans l’application à organiser et appuie sur **Ctrl + Option + Espace**.

EasyTile détecte l’autorisation sans redémarrage. Fermer sa fenêtre conserve son icône dans la barre des menus. Pour arrêter l’application, utilise **Quitter EasyTile** dans ce menu.

## Placer une fenêtre

Dans **Dispositions**, choisis la fenêtre cible, l’écran et une disposition. Clique sur une zone de l’aperçu pour déplacer et redimensionner cette fenêtre. Les zones numérotées de la palette correspondent aux touches 1 à 9. Le déplacement concerne une fenêtre à la fois.

Les huit dispositions fournies comprennent les moitiés, les tiers, les quarts, un espace principal avec une colonne latérale et une zone agrandie. L’espacement est réglable de 0 à 32 points. Le Dock et la barre des menus restent accessibles.

**Créer une disposition** ouvre une grille de 12 colonnes et 8 lignes. Dessine jusqu’à neuf zones sans chevauchement, donne un nom à la disposition et enregistre-la. Le bouton de corbeille supprime uniquement la disposition personnalisée sélectionnée.

## Raccourcis

| Action | Raccourci |
| --- | --- |
| Ouvrir ou fermer la palette | Ctrl + Option + Espace |
| Moitié gauche ou droite | Ctrl + Option + flèche gauche ou droite |
| Agrandir dans l’espace disponible | Ctrl + Option + flèche haut |
| Centrer à 80 % | Ctrl + Option + flèche bas |
| Annuler le dernier placement | Ctrl + Option + Retour arrière |
| Choisir une zone dans la palette | Touches 1 à 9 |
| Fermer la palette | Échap |

EasyTile conserve jusqu’à 30 positions précédentes pendant la session. Les raccourcis sont fixes dans cette version. Un conflit avec une autre application est signalé dans la barre d’état.

## Placement par glissement

Le menu de placement est activé par défaut. Déplace une fenêtre par sa barre de titre : les dispositions apparaissent en haut de l’écran où se trouve le pointeur. Sans relâcher la souris, survole la zone souhaitée. Un aperçu montre la position et la taille finales. Relâche la souris sur cette zone pour placer la fenêtre.

Relâche en dehors des zones ou appuie sur Échap pour conserver le déplacement libre. Le menu disparaît à la fin du glissement. Tu peux désactiver **Afficher le menu pendant le déplacement** dans **Préférences**.

EasyTile attend de constater un déplacement réel de la fenêtre avant d’afficher le menu. Une sélection de texte, un glissement de fichier ou un redimensionnement ne doivent pas le déclencher. Les applications qui n’exposent pas une fenêtre redimensionnable dans Accessibilité nécessitent un autre mode de placement.

Le menu suit le pointeur entre les écrans. Si les dispositions personnalisées dépassent l’espace disponible, le menu affiche celles qui tiennent à l’écran et conserve la disposition sélectionnée. Toutes restent accessibles depuis la palette au clavier et la fenêtre principale.

## Limites et confidentialité

EasyTile agit sur les fenêtres standard, visibles et redimensionnables des applications ouvertes. Les fenêtres réduites, les dialogues et les fenêtres d’autres bureaux ne sont pas des cibles prévues. Quitte le plein écran macOS avant de placer une fenêtre. Les applications peuvent imposer une taille minimale ; EasyTile signale alors l’ajustement.

Les dispositions et préférences sont stockées dans les préférences locales de l’application. Les titres et positions des fenêtres restent en mémoire pendant la session. EasyTile ne capture pas l’écran et n’envoie pas les fenêtres à un service distant.

Cette version ne propose pas de restauration automatique d’un ensemble d’applications ni de synchronisation. L’autorisation Accessibilité reste sous le contrôle de macOS.

## Développer

Xcode et les outils Swift sont requis.

```sh
swift test
./scripts/build.sh
open dist/EasyTile.app
```

Le script produit une application universelle pour arm64 et x86_64. Sans identité de signature, il utilise une signature locale de développement.

Pour distribuer avec un certificat Developer ID et un profil de notarisation déjà enregistré dans le trousseau :

```sh
CODE_SIGN_IDENTITY='Developer ID Application: NOM (TEAMID)' \
NOTARY_PROFILE='NOM_DU_PROFIL' ./scripts/package.sh
```

Le script soumet le DMG à Apple, joint les tickets de notarisation au DMG et à l’application, puis vérifie leur acceptation par Gatekeeper. Il crée aussi un ZIP de l’application et une archive des sources. Les certificats, clés et identifiants ne sont pas inclus dans les archives de sources.
