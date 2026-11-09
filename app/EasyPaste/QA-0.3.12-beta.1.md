# EasyPaste 0.3.12-beta.1 — trois correctifs en validation locale

9 novembre 2026. Build privé 33. La version publique reste 0.3.11 / 32.

## Curseur de capture

- Curseur natif vectoriel avec croix, cercle et contour blanc/noir contrasté, point actif centré.
- Coordonnées locales à l’écran, origine en haut à gauche, en points ; les dimensions de la sélection restent exprimées en pixels comme auparavant.
- Réapplication du curseur à l’entrée, au déplacement et après distribution de l’événement par la fenêtre, y compris sur une fenêtre non principale.
- Deux zones de suivi : événements de souris actifs sur toutes les fenêtres ; `cursorUpdate` actif dans l’application. AppKit ne prend pas en charge `cursorUpdate` avec `activeAlways`.
- Les fenêtres de sélection partagent la position globale du pointeur, même lors d’un glissement toujours adressé à la fenêtre de départ. Le texte de coordonnées n’apparaît que sur l’écran contenant le pointeur.
- Aucun timer, empilement de curseurs ni reconstruction d’image à chaque mouvement. Annulation et fin rétablissent la flèche.
- La sélection d’une zone reste limitée à l’écran de départ ; ce correctif garantit la continuité du curseur et ne crée pas une capture réunissant plusieurs écrans.

## Presse-papiers universel

- Détection du marqueur `com.apple.is-remote-clipboard`.
- Lecture du contenu distant sur une file série de fond : au plus une lecture distante à la fois, sans bloquer la collecte de nouvelles copies locales.
- Un contenu annoncé mais encore indisponible est réessayé avec délai croissant et plafond de huit relances. Une nouvelle révision annule l’attente de l’ancienne.
- Résultats invalidés si une nouvelle copie est arrivée, si la collecte est mise en pause/arrêtée ou si les exclusions ont changé.
- Origine affichée « Autre appareil Apple », sans attribuer le contenu à l’application Mac au premier plan ni lire son URL.
- Marqueurs confidentiels/transitoires et exclusions explicites de l’application source respectés.
- Ni écriture ni effacement du presse-papiers pendant l’import. L’image originale est conservée.
- Limite : dépend de la disponibilité du contenu dans le presse-papiers universel macOS ; aucun mécanisme privé ne force Handoff ou le transfert réseau.

## Retour au début de la barre

- Une demande distincte de défilement est créée lorsque la nouvelle copie devient visible dans les résultats.
- Le pont natif remet la vue à gauche une seule fois par demande, sans animation. La requête est consommée après l’application.
- Une recopie du même contenu fonctionne même lorsque l’identifiant sélectionné ne change pas.
- La navigation explicite annule une demande en attente ; une simple réouverture sans nouvelle copie conserve la position.
- La première tentative via `ScrollViewReader` et une tâche différée a provoqué 21 échecs dans les tests existants de molette. Cette approche a été retirée avant installation ; les tests passent avec la remise à zéro native.

## Résultats automatisés

- 33 tests ciblés réussis après correction du conflit de défilement, dont contrôle de la vue native en modes normal/compact.
- Suite complète finale : **348 tests, aucun échec**, 91,038 secondes, Release, SDK déclaré 27.0 et minimum macOS 15.
- Tests supplémentaires : curseur/coordonnées/bords d’écran et fenêtres simulées à gauche/au-dessus ; contenu distant fourni tardivement sans changement de révision ; confidentialité ; image originale ; pause et remplacement pendant un import ; absence de doublons ; relances bornées ; retour réel de l’offset après recherche et recopie.
- `git diff --check` réussi.
- Construction universelle par `scripts/build.sh`, Developer ID habituel, vérification stricte de signature réussie.
- Installée à `/Applications/EasyPaste.app`. Sauvegarde précédente : `/Users/k2r59/Library/Caches/EasyPaste-local-install/backup-2026-11-09/EasyPaste.app`.
- Au repos après lancement : relevé ponctuel 0,0 % CPU, 130 720 Ko RSS. Ce relevé n’est pas un benchmark de durée.

## Validation réelle encore requise avant push

- Session ouverte sur le Mac : la commande OCR ouvre la sélection et expose les coordonnées dans l’interface.
- Deux écrans disponibles : LC49G95T 5120 × 1440 points, échelle 1 ; LG ULTRAFINE 2560 × 1440 points à droite, échelle 2.
- L’utilisateur a accepté un essai iPhone → Mac. Trois questions sont en attente : continuité du curseur sur les deux écrans ; texte et image depuis l’iPhone sans collage préalable ; retour au début après recherche et nouvelle copie.
- Aucun succès physique multi-écran ou Handoff n’est revendiqué tant que ces essais ne sont pas confirmés. Pas de publication ni de push de ces correctifs à ce stade.

Logs locaux : `/tmp/easypaste-three-fixes-tests.log`, `/tmp/easypaste-three-fixes-full.log`, `/tmp/easypaste-three-fixes-build.log`.

## Contre-vérification réelle et révision beta.2 — 9 novembre

- L’utilisateur confirme le curseur (« le .1 c’est ok lui il fonctionne »).
- Un texte puis une photo copiés sur son iPhone sont arrivés sans collage préalable sur le Mac, avec l’origine « Autre appareil Apple ».
- La photo est fournie par Handoff sous forme d’un fichier JPEG temporaire : beta.1 l’affichait comme fichier. Beta.2 incorpore les pixels d’une photo distante unique dans le payload image (PNG sans perte, pleine résolution, orientation respectée), afin d’offrir miniature et aperçu et de ne plus dépendre de la durée de vie du fichier temporaire. Le presse-papiers système n’est pas modifié. Les copies Finder locales et sélections de plusieurs fichiers gardent leur comportement.
- Le reset natif unique de beta.1 a échoué dans un vrai cycle recherche/défilement/fermeture/nouvelle copie/réouverture. Ne pas considérer les 348 tests comme une preuve de résolution de ce cas.
- Beta.2 renouvelle uniquement l’identité du ScrollViewReader des cartes lorsqu’une nouvelle copie devient visible : les restaurations tardives de LazyHStack ne peuvent plus reprendre l’ancien offset. Pas de timer ni réinitialisation sur les mises à jour ordinaires ; recherche, en-tête et aperçu ne sont pas reconstruits. Le routage natif de molette de production est inchangé.
- Le test natif normal/compact couvre désormais 600 éléments, un filtre qui masque la nouvelle copie, une recopie du même élément et la réouverture sans nouvelle copie.
- Trois tests supplémentaires couvrent les photos JPEG/PNG reçues comme fichiers, l’aperçu après disparition du fichier temporaire, les dimensions originales, le fichier encore absent, le comportement Finder inchangé, les faux JPEG contenant du SVG et la limite de taille.
- 14 tests ciblés passés avant ajout des trois tests photos. Suite complète beta.2 : **351 tests, aucun échec**, 59,185 secondes (Release, SDK 27).
- Beta.2 / build 34 construite universelle et signée Developer ID, installée dans `/Applications/EasyPaste.app`. Beta.1 sauvegardée dans `/Users/k2r59/Library/Caches/EasyPaste-local-install/backup-2026-11-09-beta1/EasyPaste.app`.
- À la fermeture de beta.1, un échantillonnage du processus a montré une attente AppKit `CFPasteboardResolveAllPromisedData` → `_NSRTFPboardTypeConverter`. Le processus a fini par se terminer ; la tentative de SIGTERM est arrivée après sa disparition. Pas de réinitialisation du presse-papiers. À surveiller : ce blocage de fermeture n’est pas déclaré corrigé.
- La recherche réelle « capture » et son défilement jusqu’aux éléments de 21–22 jours ont été effectués dans beta.2. Barre ensuite fermée ; nouvelle copie photo iPhone demandée pour contrôler l’aperçu et le reset. Validation réelle beta.2 encore en attente.
- Logs beta.2 : `/tmp/easypaste-iphone-scroll-beta2-tests.log`, `/tmp/easypaste-beta2-full.log`, `/tmp/easypaste-beta2-build.log`.

## Validation beta.3 et limite macOS confirmée

- Photo réelle suivante : fichier JPEG 4 343 076 octets présent dans le conteneur de Handoff. Les attributs sont lisibles ; la lecture des octets est refusée (EPERM / Cocoa permission).
- `NSPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])` et `startAccessingSecurityScopedResource()` ajoutés : le refus persiste dans l’application Developer ID installée, pas seulement dans l’outil de test.
- Journaux système du 9 novembre à 15:21:58 : `kTCCServiceSystemPolicyAppDataDetailed`, refus avec `access requires indirect object have an associated app bundle`. Le système protège le conteneur `group.com.apple.coreservices.useractivityd`. Aucun changement de permissions, entitlement privé ou accès disque complet ajouté.
- **Aperçu de cette photo iPhone NON résolu sur ce Mac.** Ne pas annoncer les trois points entièrement fonctionnels. L’import des images PNG/TIFF et des fichiers photo accessibles fonctionne dans les tests, mais ce cas réel reste bloqué par macOS.
- Beta.4 conserve le fichier dans l’historique si la lecture de ses pixels est refusée et explique que macOS bloque l’aperçu. La copie n’est plus abandonnée sur l’erreur. Test dédié à un fichier non lisible.
- Lecture distante déjà présente au lancement : révision réimportée une seule fois, puis dédupliquée normalement. Le démarrage sur un presse-papiers local ne change pas.
- Les formats distants non annoncés ne sont plus demandés via les convertisseurs automatiques AppKit (la lecture du texte se fait depuis les représentations capturées). Cela réduit les demandes de conversion inutiles ; le blocage de fermeture observé n’est pas déclaré définitivement corrigé.
- **Défilement vérifié dans la véritable application beta.3 installée** : recherche « capture », déplacement au bout jusqu’à 21–22 jours, fermeture ; création d’un document TextEdit séparé, copie de `EASYPASTE QA RETOUR GAUCHE 0911 B3`, puis ⇧⌘V. Le contrôle AX montre ce texte en première tuile. Une image copiée ensuite par l’utilisateur prend la première place ; capture d’écran confirmant le bord gauche, la nouvelle image et le texte de contrôle côte à côte. L’origine Slack du texte de test est liée au premier plan pendant l’injection en arrière-plan de l’outil ; ne pas la présenter comme un bug de provenance reproduit normalement.
- Document de test `Sans titre 2` laissé dans TextEdit ; aucun document utilisateur supprimé. Le précédent `Sans titre` a reçu de la saisie concurrente et n’a pas été écrasé.
- **352 tests, zéro échec**, 59,044 s, Release, suite complète beta.4. Log `/tmp/easypaste-beta4-full.log`.
- Beta.4 /36 en cours de construction locale. Pas de publication ni de push.

### État final local de cette passe

Beta.4 /36 **installée et relancée**, interface d’historique visible, focus recherche présent. Signature Developer ID vérifiée avant remplacement. Sauvegarde beta.3 : `/Users/k2r59/Library/Caches/EasyPaste-local-install/backup-2026-11-09-beta3/EasyPaste.app`. Public inchangé (0.3.11 /32).

Ne pas demander une nouvelle copie iPhone : l’utilisateur en a déjà effectué plusieurs. Son dernier JPEG réel n’a pas pu être décodé à cause du refus macOS documenté. Le fallback de conservation du fichier en cas d’accès refusé est couvert par le nouveau test, mais n’a pas été revalidé sur ce JPEG réel après installation beta.4 (le presse-papiers contient depuis d’autres copies). Ne pas confondre « références de fichiers conservées » et « octets de la photo sauvegardés » : sans accès au fichier temporaire, les octets ne sont pas incorporés et le lien peut expirer. L’aperçu iPhone n’est donc pas validé ; aucune publication/push autorisé implicitement par ces tests.


### Validation réelle finale — 9 novembre 2026, 0.3.12 /37

Cet état remplace le blocage iPhone décrit dans les passes précédentes.

- Version locale installée : 0.3.12, build 37, Developer ID, sans suffixe beta. Aucune publication effectuée à ce stade.
- Autorisation explicite de l’utilisateur accordée au seul dossier Apple `shared-pasteboard`, via le sélecteur macOS ; bookmark de lecture seule. Aucun accès complet au disque.
- L’utilisateur a recopié une image directement depuis la galerie de son iPhone, sans collage sur le Mac. L’image est arrivée automatiquement en première tuile, avec origine « Autre appareil Apple », miniature, dimensions 1320 × 1097 px et poids 250 ko.
- Vérification visuelle effective de la miniature puis de l’aperçu agrandi : image rendue, dimensions correctes et texte OCR disponible. Ce n’est plus une simple référence de fichier sans miniature. Aucun contenu privé de l’image ajouté au dépôt.
- Suite complète Release de régression : 355 tests, zéro échec, 62,046 s ; `/tmp/easypaste-0312-regression.log`. Les tests couvrent notamment les données distantes différées, les photos incorporées, les limites du dossier autorisé, l’annulation et le retour au début de l’historique.
- Les anciens fichiers de transfert avaient expiré : leur récupération rétroactive n’a pas été validée positivement. Le transfert réel neuf depuis la galerie est validé.
- Le correctif de défilement horizontal déjà publié reste inchangé. Aucun test ne justifie une garantie absolue d’absence de bugs.
