# EasyShoot

EasyShoot est une application macOS locale de capture, d’annotation et de montage vidéo. Le code source est disponible sous [licence MIT](LICENSE). La version 0.3 contient un espace de capture, une bibliothèque visuelle, un éditeur d’annotations et un éditeur vidéo avec timeline.

## Compiler et lancer

Prérequis : macOS 15 ou version ultérieure, Xcode et Swift 6.

```sh
cd app/EasyShoot
./scripts/build.sh
open dist/EasyShoot.app
```

L’application apparaît dans la barre de menus avec une icône de viseur. Le script génère une application signée localement, destinée aux essais sur ce Mac. La distribution à d’autres utilisateurs nécessitera une signature Developer ID et une notarisation.

## Installer sur un autre Mac

La distribution universelle contient les exécutables Intel et Apple Silicon. Elle nécessite macOS 15 ou une version ultérieure.

1. Ouvrir `EasyShoot-0.3.0-universal.dmg`.
2. Glisser EasyShoot dans le raccourci Applications.
3. Ouvrir EasyShoot depuis Applications.

Créer le DMG et les archives de l’application et du code source :

```sh
./scripts/package.sh
```

Le script écrit les fichiers dans `dist/` et calcule leurs empreintes SHA-256. L’image disque contient aussi la licence MIT et les instructions d’installation.

La signature locale de développement ne suffit pas pour éviter les alertes Gatekeeper sur un autre Mac. Pour publier une version notarisée, configurer un certificat Developer ID Application et un profil `notarytool` dans le trousseau, puis lancer :

```sh
CODE_SIGN_IDENTITY="Developer ID Application: VOTRE IDENTITÉ" \
NOTARY_PROFILE="VOTRE PROFIL DU TROUSSEAU" \
./scripts/package.sh
```

Le script signe l’application et le DMG, soumet le DMG à Apple, puis y attache le ticket de notarisation. La signature et la notarisation nécessitent les identifiants de distribution du développeur. L’installation sur un Mac Intel physique reste à vérifier.

## Utiliser EasyShoot

1. Ouvrir « Autoriser la capture » pour accéder aux autorisations macOS.
2. Activer EasyShoot dans les réglages d’enregistrement de l’écran. Relancer l’application si macOS le demande.
3. Choisir « Capturer une zone », une fenêtre ou l’écran principal.
4. Choisir « Copier », « Enregistrer » ou « Annoter » dans l’aperçu flottant. Pour une vidéo, choisir « Monter la vidéo » pour ouvrir son éditeur.
5. Dans l’éditeur, annoter l’image, puis choisir « Copier » ou « Exporter ».

Le raccourci global **⌃⌥⌘2** ouvre la sélection de zone. Pour extraire du texte à l’écran, appuyer sur **⌃⌥⌘T**, puis tracer un rectangle à la souris. EasyShoot reconnaît le texte et le copie dans le presse-papiers. Une confirmation affiche le nombre de caractères copiés sans interrompre le travail. Appuyer sur Échap pour annuler la sélection. Dans l’éditeur, utiliser **⌘Z** pour annuler une annotation, **⌘C** pour copier l’image et **⌘S** pour l’exporter.

Les captures originales et les vidéos restent dans `~/Library/Application Support/EasyShoot/Captures`. Les annotations restent en mémoire tant que l’éditeur est ouvert. Exporter l’image pour les conserver avant de quitter.

## Fonctions présentes

- Capture de zone, de la dernière zone, d’une fenêtre et de l’écran principal.
- Sélection de zone sur plusieurs écrans et retardateur de cinq secondes avant la sélection.
- Import d’image et ouverture depuis le presse-papiers.
- Flèches, cadres, ellipses, dessin libre, surlignage, texte et étapes numérotées.
- Masquage par aplat noir opaque, annulation et export PNG aux dimensions d’origine.
- OCR français et anglais avec Apple Vision, exécuté sur le Mac.
- Épinglage dans une fenêtre flottante redimensionnable.
- Aperçu flottant après une image ou une vidéo, avec copie, enregistrement, ouverture, accès au Finder et glisser-déposer.
- Bibliothèque locale avec miniatures et dates.
- Vidéo MP4 de l’écran principal à 30 images/s, avec le son système, via ScreenCaptureKit.
- Capture défilante verticale avec détection de stabilité, raccords d’images et contrôle des doublons.
- Montage d’une vidéo source : coupe, division, suppression et réorganisation de segments, vitesse de 0,25× à 4×, recadrage et réglage audio.
- Export MP4 en résolution source, 1080p ou 720p, sans agrandir une petite vidéo.

## Limites de cette version

EasyShoot ne couvre pas encore toutes les fonctions de CleanShot X. Les GIF, le microphone, la caméra, les zooms animés, les transitions, l’assemblage de plusieurs fichiers vidéo, le masquage des icônes du bureau, les arrière-plans décoratifs et les projets enregistrables restent à développer.

La capture défilante fonctionne vers le bas et s’arrête à 40 mégapixels ou 50 000 pixels de hauteur. Elle exige un recouvrement visible entre les portions. Exclure les en-têtes et pieds de page fixes de la zone sélectionnée. Les contenus animés, les motifs identiques répétés et les grands sauts de défilement peuvent empêcher le raccord. Le défilement horizontal n’est pas pris en charge.

L’export, l’OCR, les raccords et le moteur de montage ont des contrôles automatisés. La capture directe nécessite l’autorisation macOS d’enregistrement de l’écran. Les tests de raccord utilisent des images connues ; ils ne remplacent pas un essai dans chaque application cible.

## Capturer une page défilante

1. Afficher le début de la page ou de la conversation à capturer.
2. Choisir « Capture défilante » dans EasyShoot ou dans son menu.
3. Sélectionner à la souris la zone de contenu, en évitant les barres fixes.
4. Faire défiler vers le bas dans l’application d’origine, d’environ une demi-zone à chaque fois.
5. Attendre une seconde après chaque mouvement pour laisser EasyShoot ajouter la portion stable.
6. Choisir « Terminer » pour assembler le PNG et afficher les actions de copie ou d’enregistrement.

Le panneau indique le nombre de portions et la hauteur de l’image finale. S’il affiche « Raccord introuvable », remonter légèrement, puis avancer moins loin. EasyShoot conserve les portions déjà assemblées. « Pause » suspend l’acquisition et « Reprendre » la réactive. Fermer le panneau annule la session.

Le panneau se place hors de la zone lorsque l’espace disponible le permet. S’il chevauche la sélection, il se masque pendant chaque prise pour ne pas apparaître dans le PNG.

## Monter une vidéo

1. Choisir « Montage vidéo » sur l’accueil, « Monter une vidéo… » dans le menu ou l’icône de ciseaux de l’aperçu vidéo.
2. Ouvrir un fichier MP4, MOV ou M4V. Le fichier source reste intact.
3. Placer la tête de lecture dans la timeline, puis choisir « Diviser ici » pour créer des segments.
4. Sélectionner un segment pour ajuster son début, sa fin ou sa vitesse. Choisir « Appliquer la coupe » après avoir réglé les bornes.
5. Utiliser « Avancer », « Reculer » et « Supprimer le segment » pour organiser les parties conservées.
6. Choisir un format dans « Cadrage » : original, 16:9, 9:16, carré ou 4:3. Les curseurs actifs déplacent la zone conservée.
7. Régler le volume dans « Audio » ou activer « Retirer la piste audio » pour exporter une vidéo sans son.
8. Choisir la résolution, puis « Exporter le MP4 ». L’aperçu flottant propose ensuite de copier le fichier ou de l’enregistrer ailleurs.

La barre Espace lance ou suspend la lecture. **⌘B** divise le segment sous la tête de lecture, **⌘Z** annule une modification et **⌘E** lance l’export. Pour retirer un passage au milieu, diviser avant et après ce passage, sélectionner le segment central, puis le supprimer.

L’aperçu et l’export partagent le même montage AVFoundation. L’export contient les pistes audio conservées, avec les mêmes coupes et changements de vitesse. L’option de retrait audio supprime réellement les pistes du MP4. Les modifications restent en mémoire : exporter avant de quitter.

## Connecter un client MCP

EasyShoot intègre un processus MCP local en `stdio`. Aucun serveur distant, port réseau, compte ou service supplémentaire n’est nécessaire. Le client lance le même exécutable avec `--mcp`. Les modes MCP et de test ne démarrent pas l’application graphique ; ils ne remplacent donc pas son instance dans LaunchServices.

Les préférences contiennent un bouton « Copier la configuration ». La configuration JSON suivante convient aux clients qui utilisent `mcpServers` :

```json
{
  "mcpServers": {
    "easyshoot": {
      "command": "/Applications/EasyShoot.app/Contents/MacOS/EasyShoot",
      "args": ["--mcp"]
    }
  }
}
```

Pour Codex, ajouter cette entrée à la configuration TOML :

```toml
[mcp_servers.easyshoot]
command = "/Applications/EasyShoot.app/Contents/MacOS/EasyShoot"
args = ["--mcp"]
```

Par défaut, le MCP lit uniquement le dossier des captures EasyShoot. Ajouter `--read-root` et un chemin absolu dans `args` pour autoriser un autre dossier. Le processus écrit uniquement ses nouvelles captures dans le dossier d’EasyShoot. Les lectures refusent les chemins qui sortent des racines autorisées, y compris par un lien symbolique.

| Outil | Action |
| --- | --- |
| `get_status` | Lire les permissions et les dossiers autorisés. |
| `capture_screen` | Capturer l’écran principal et retourner un aperçu. |
| `capture_region` | Capturer un rectangle défini par `x`, `y`, `width`, `height` ; sans coordonnées, demander une sélection à la souris. |
| `extract_text` | Extraire le texte depuis `path`, des coordonnées ou une sélection à la souris ; retourner le texte sans modifier le presse-papiers. |
| `list_captures` | Lister les captures et vidéos locales. |
| `open_editor` | Ouvrir une image dans l’application graphique indépendante. |

Les coordonnées utilisent les points macOS, à partir du coin supérieur gauche de l’écran principal. Le protocole prend en charge les versions MCP à initialisation de `2024-11-05` à `2025-11-25`. La capture exige l’autorisation macOS d’enregistrement de l’écran. L’OCR d’un fichier autorisé fonctionne sans cette permission.

Après modification d’une autorisation, relancer le client MCP si nécessaire. Dans l’application, utiliser « Relancer EasyShoot » depuis la barre de menus. Une réouverture de l’application affiche son espace de travail même si toutes ses fenêtres ont été fermées.

## Lancer les contrôles

```sh
./scripts/build.sh
dist/EasyShoot.app/Contents/MacOS/EasyShoot --self-test
dist/EasyShoot.app/Contents/MacOS/EasyShoot --feature-tests
dist/EasyShoot.app/Contents/MacOS/EasyShoot --capture-tests
python3 scripts/test-mcp.py
```

Les contrôles vérifient les dimensions de l’export sur écran Retina, les pixels masqués, l’annulation et la reconnaissance du texte. Ils écrivent une image de contrôle dans le dossier temporaire `EasyShoot-tests` du système.

Les six tests MCP vérifient l’initialisation, la découverte des outils, les erreurs de protocole, les arguments invalides, l’OCR local et les restrictions de lecture.

Les contrôles supplémentaires génèrent leurs images et vidéos avec les API natives. Ils vérifient les raccords Retina au pixel près, les doublons, les sauts refusés, les transitions de la session de capture et l’enregistrement du résultat. Pour le montage, ils contrôlent la durée, les couleurs des segments réordonnés, les dimensions du cadrage, l’orientation, la conservation ou la suppression de l’audio et l’intégrité de la source. Les fichiers de contrôle restent dans le dossier temporaire `EasyShoot-feature-tests` du système.

Les essais d’interface ont vérifié la division et la suppression d’un segment, le recadrage carré et un export MP4 depuis l’éditeur. Les 32 contrôles de capture défilante et de montage ont également réussi sur trois exécutions consécutives après correction de la limite de durée audio.

## Autorisations de capture

Les captures de l’application et la capture défilante utilisent ScreenCaptureKit dans le processus signé d’EasyShoot. Une erreur de capture met la capture défilante en pause : elle ne relance pas les demandes en boucle.

Ouvre EasyShoot depuis Applications. Clique sur « Autoriser la capture », puis active cette copie dans Réglages Système → Confidentialité et sécurité → Enregistrement de l’écran et de l’audio système. Si macOS demande de quitter l’app, rouvre-la depuis Applications après activation. Les demandes de confirmation imposées par macOS restent sous le contrôle du système.

## Nouveautés 0.3.0

Mises à jour intégrées depuis le menu EasyShoot, sons de capture et de copie facultatifs, réglages simplifiés, captures Retina et protection contre les portions noires pendant la capture défilante. Les portions déjà réussies restent enregistrables si le contenu suivant devient indisponible. Les captures protégées, les en-têtes fixes et les grands sauts ne sont pas pris en charge.

- [Notes de version](docs/RELEASE-0.3.0.md)
- [Contrôles et limites](QA-0.3.0.md)
- [Publication des mises à jour](docs/UPDATES.md)
- [Composants tiers](THIRD-PARTY-NOTICES.md)

Les versions 0.2.x nécessitent une dernière installation manuelle. Ensuite, utiliser « Rechercher des mises à jour… ». Vérifier automatiquement est facultatif ; l’installation reste à la demande.
