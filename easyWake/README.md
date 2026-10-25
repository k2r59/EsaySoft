# EasyWake

Petite application macOS native, en français, sans dépendance externe. Compatible macOS 13 et versions suivantes.

## Utilisation

Ouvrir `build/EasyWake.app`, choisir une durée et cliquer sur **Activer EasyWake**. L’application empêche la veille automatique du Mac et de son écran pendant la session. Elle démarre toujours en pause.

L’option souris effectue un aller-retour de 1 pixel toutes les 15, 30, 60 ou 120 secondes. Elle attend au moins 5 secondes sans saisie ni mouvement et ne simule aucun clic. Pour l’autoriser : **Réglages Système → Confidentialité et sécurité → Accessibilité → EasyWake**. Si nécessaire, ajouter l’application avec le bouton `+`, puis la relancer. Le maintien en éveil fonctionne même sans cette autorisation.

La croix ferme seulement la fenêtre : EasyWake reste accessible via l’icône **soleil**, sans texte, dans la barre de menus. Le soleil est plein pendant une session et en contour à l’arrêt. Cliquer dessus ouvre un menu avec l’état, le temps restant, le bouton marche/arrêt, un sous-menu de durée et un sous-menu d’intervalle, ainsi que l’option souris. Les réglages sont synchronisés avec la fenêtre. La durée se choisit avant de lancer une session ; l’intervalle reste modifiable pendant son exécution.

**Arrêter EasyWake**, la fin de la durée choisie ou **Quitter EasyWake** libère le maintien en éveil. La mise en veille manuelle et la fermeture du capot restent gérées par macOS ; l’application ne contourne pas le verrouillage ou les politiques de sécurité.

## Construire

Avec Xcode ou les outils de développement Apple installés :

```sh
bash build.sh
open build/EasyWake.app
```

La compilation cible l’architecture du Mac utilisé. Pour compiler un binaire universel, lancer `ARCHITECTURES="arm64 x86_64" bash build.sh`. La signature ad hoc convient à l’utilisation locale ; la distribution à d’autres Mac nécessiterait une signature Developer ID et une notarisation.

## DMG d’installation

```sh
bash build-dmg.sh
```

Le script compile une version universelle Apple Silicon et Intel (macOS 13 minimum), puis produit `build/releases/EasyWake-1.1-universal.dmg` et son empreinte SHA-256. Le disque contient l’application, un raccourci vers Applications et les instructions d’installation. Glisser l’application dans Applications, éjecter le disque, puis lancer la copie installée.

Le DMG est compressé et en lecture seule. Il n’est pas signé ni notarisé ; l’application embarquée conserve une signature ad hoc. La signature Developer ID et la notarisation sont prévues pour une étape ultérieure. Le script ne modifie pas l’application déjà installée dans Applications.

## Vérifier

```sh
build/EasyWake.app/Contents/MacOS/EasyWake --self-test
```

Ce contrôle acquiert puis libère les assertions système pour les sessions temporisées et illimitées. Pour vérifier une session depuis le terminal, utiliser `pmset -g assertions` : le processus `EasyWake` doit posséder ses assertions uniquement lorsque la session est active.

## Lancer au démarrage

Dans le menu **EasyWake**, cocher **Lancer au démarrage** pour ouvrir automatiquement l’application à chaque connexion au Mac. Décocher cette option la retire des éléments d’ouverture. Le réglage utilise le service natif de macOS et reflète aussi les changements effectués dans les Réglages Système. Si macOS attend une autorisation, le menu affiche un tiret et propose un accès aux réglages de connexion.

Le lancement automatique ouvre l’application en pause : cliquer sur **Activer EasyWake** pour commencer le maintien en éveil. Conserver l’application au même emplacement après l’activation du lancement automatique.
