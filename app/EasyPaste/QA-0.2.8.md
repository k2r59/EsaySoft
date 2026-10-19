# EasyPaste 0.2.8 : SVG et pipette

Version 0.2.8, build 13. Aucun paquet externe ajouté ; licence MIT inchangée.

## Pipette

Le menu de la barre macOS propose **Prélever une couleur…**. La sélection utilise [NSColorSampler](https://developer.apple.com/documentation/appkit/nscolorsampler), la loupe native du système. Le résultat est converti en sRGB, arrondi sur huit bits par canal, enregistré dans l’historique puis copié en HEX. La fenêtre affiche la couleur, le HEX et le RGB. Les lignes de valeurs sont cliquables sur toute leur surface.

L’annulation ne modifie ni l’historique ni le presse-papiers. Les appels répétés et les doubles réponses sont ignorés. La pipette n’est pas lancée pendant une capture, un enregistrement, une annotation ou le chargement de l’historique.

![Rendu natif avec une couleur de démonstration](docs/color-picker.png)

## SVG : périmètre et contrôles

Le contenu SVG est reconnu comme texte structuré. Les représentations `public.svg-image` et `image/svg+xml` sont conservées à la collecte ; aucune rasterisation n’y est effectuée. Les fichiers `.svg` utilisent l’aperçu contrôlé, sans Quick Look. Les SVGZ doivent être décompressés. Un SVG présenté comme PNG ou TIFF est refusé par le chemin de décodage raster.

Avant tout rendu, le document est analysé puis reconstruit à partir d’une liste d’éléments et d’attributs autorisés. Les scripts, événements, HTML, animations, ressources externes ou embarquées, DTD, entités personnalisées, filtres, `<use>` et feuilles de style sont refusés. Un sous-ensemble des styles de présentation en ligne est converti en attributs. Les références locales visent uniquement les dégradés ou les découpes et sont contrôlées contre les cycles. Les textes et attributs sont échappés à la reconstruction.

La politique s’inspire des restrictions de contenu du [mode statique sécurisé de SVG](https://www.w3.org/TR/SVG/conform.html). Ce rendu ne prétend pas prendre en charge toute la spécification SVG. Un élément non pris en charge bloque l’aperçu et affiche une erreur ; le source reste accessible.

Le moteur natif reçoit seulement le document reconstruit, dans un processus séparé lancé avec `--render-svg`. Ce mode démarre avant l’initialisation de l’app, du presse-papiers ou de l’historique. Il revalide l’entrée, produit un PNG puis quitte. Il ne s’agit pas d’une sandbox système : la séparation vise à contenir les erreurs et les lenteurs du rendu. Les risques d’un lecteur tiers ne sont pas couverts par ce contrôle.

Les vues **Source** et **Aperçu** fournissent le SVG reconstruit à la copie et à l’export. **Original** conserve le texte enregistré et demande une confirmation avant de le transmettre. La copie et le glisser-déposer depuis une carte SVG sont également contrôlés. Les références de fichiers restent des références originales ; elles sont validées avant la copie ou le glisser-déposer, mais peuvent être modifiées extérieurement ensuite. Le bouton **Ouvrir** remet explicitement le fichier à son application externe.

## Limites de ressources

| Contrôle | Limite |
| --- | --- |
| Entrée et SVG reconstruit | 512 Kio |
| Éléments / profondeur | 2 000 / 32 |
| Valeurs numériques / références locales | 50 000 / 256 |
| PNG | Grand côté de 2 048 pixels, sortie de 20 Mo maximum |
| Rendu | Délai de six secondes, puis arrêt forcé après 0,5 seconde si nécessaire |
| Temps CPU du processus de rendu | Limite souple de quatre secondes, dure de cinq secondes |

L’analyse tourne en arrière-plan. Le rendu est annulé à la fermeture ou au changement de document. Le PNG conserve la transparence et un profil sRGB explicite ; le SVG reconstruit reste vectoriel. Aucun rendu n’est lancé simplement pour collecter une copie.

## Vérifications du 19 octobre 2026

La suite complète comporte **146 tests**. Deux passes Release ont réussi sans échec, en environ **21,8 et 20,8 secondes**, après une première passe intermédiaire de 142 tests. Les historiques et presse-papiers des tests sont isolés des données personnelles.

- Pipette : HEX/RGB exacts, conversion Display P3, noir, blanc, gris, enregistrement durable, annulation, double réponse et refus pendant l’enregistrement vidéo.
- Fenêtre de la pipette : rendu natif hors écran, dimensions et inspection de l’image de démonstration.
- SVG : formes, tracés, dégradés, styles simples, espaces de noms, échappement, CDATA et stabilité de la reconstruction.
- Corpus de scripts, événements, entités, liens externes, injections CSS, références invalides ou circulaires et noms d’éléments confus.
- XML incomplet, dimensions non finies ou trop petites, profondeur, taille, nombre d’éléments et expansion du document reconstruit.
- 352 mutations par suppression de caractères : aucun contenu actif admis par les assertions, aucun crash observé.
- Fichiers trop gros, SVGZ et faux PNG/TIFF ; conservation du source.
- Rendu par le véritable exécutable enfant : dimensions, transparence et valeurs RGB du PNG. Le profil sRGB est vérifié séparément des canaux stockés.
- Annulation, exécutable absent, sortie en erreur et fermeture du canal d’entrée. Un auxiliaire ignorant SIGTERM est arrêté en environ 6,6 secondes par le mécanisme de délai.
- Copie et glisser-déposer contrôlés (texte, RTF et fichier), refus d’un SVG actif sans effacer le presse-papiers, édition, variante adjacente, source original intact et transfert du PNG sans source SVG.
- Vue native SVG à 600 × 390, fonds et commandes ; rendu inspecté hors écran.
- Régression de Markdown, JSON, SQL, CSV, XML, de l’historique, des captures, de l’annotation et des vidéos.

Le test d’analyse de 1 900 tracés observe un intervalle maximal d’environ **6,1 ms** entre les réveils du thread principal. C’est une mesure sur le Mac de développement, pas une garantie pour tous les documents ou toutes les machines.

La sélection physique d’un pixel à la souris, le passage réel entre plusieurs moniteurs, VoiceOver et l’exécution sur Mac Intel restent à vérifier. L’image de la pipette utilise une couleur de démonstration ; elle ne constitue pas un essai manuel du sélecteur système. La suite vidéo utilise ses fixtures existantes, sans nouveau tournage avec la webcam.

## Reproduire

Depuis `app/EasyPaste` :

```sh
EASYPASTE_LAYOUT_SNAPSHOTS="$PWD/.build/svg-color-snapshots" swift test -j 2 -c release
```

Les tests du processus enfant attendent l’exécutable produit par SwiftPM dans `.build/out/Products/Release/EasyPaste` sur cette configuration Xcode.
