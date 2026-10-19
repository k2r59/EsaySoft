# EasyPaste 0.2.7 : aperçu Markdown

Version 0.2.7, build 12. Ajout du Markdown aux formats de texte existants. Aucun paquet externe ajouté ; licence MIT inchangée.

## Comportement

Une détection bornée reconnaît les principales marques du Markdown sans parser tout le presse-papiers sur le thread principal. Les objets JSON, tableaux JSON, documents XML et requêtes SQL conservent leur priorité. Le choix manuel reste disponible dans **Formater…**.

L’éditeur propose **Original**, **Source** et **Aperçu**. Modifier depuis l’aperçu ouvre le source ; **Terminer** revient au rendu. Copier, exporter ou enregistrer conserve les octets du source. L’export utilise `.md`. La création d’une variante et le remplacement confirmé réutilisent les transactions chiffrées de l’historique.

L’analyse utilise les [options Markdown de Foundation](https://developer.apple.com/documentation/foundation/attributedstring/markdownparsingoptions) et ses indications de présentation. L’affichage utilise un NSTextView sélectionnable, avec recherche native et tableaux NSTextTable. Titres, gras, italique, texte barré, listes imbriquées et numérotées, cases à cocher, citations, liens, séparateurs, blocs de code et tableaux sont rendus. La syntaxe incomplète reste généralement lisible comme du texte.

Le contenu HTML est du texte inerte. Aucune image distante ni locale n’est chargée : son texte alternatif apparaît. Les liens HTTP, HTTPS et mailto ne s’ouvrent qu’après un clic ; les autres schémas ne sont pas actifs.

## Vérifications du 19 octobre 2026

La suite complète comprend 119 tests, dont 20 ajoutés pour Markdown. Deux passes complètes en Release ont réussi sans échec avant la fabrication de l’installateur (environ 16,4 s et 14 s). Les essais utilisent des historiques temporaires chiffrés et des presse-papiers nommés, sans modifier l’historique personnel.

- Conservation exacte du source, BOM, retours CRLF, Unicode et caractères échappés.
- Hiérarchie des titres, styles en ligne, sauts forcés, listes imbriquées, paragraphes de continuation, tâches, citations et code littéral.
- Coordonnées et alignement des cellules, tableaux larges et images sans description.
- Liens sûrs, refus des schémas actifs non autorisés et absence de pièces jointes chargées par le rendu.
- 928 variantes obtenues par troncature ou suppression de caractères : aucune modification du source, aucun crash observé.
- Marqueurs non fermés, Markdown vide, blocs de code interrompus et tableaux incomplets.
- Entrées répétitives de 100 000 caractères, citations profondément imbriquées, budgets de taille et annulation.
- Copie complète d’un document dont l’aperçu est abrégé, édition, variante, remplacement, changements rapides de format et de vue.
- Vue native hors écran à 690 × 700 : disposition, texte sélectionnable, recherche, passage au source, saisie et retour au rendu. Capture du rendu inspectée.
- Régression des formats JSON, SQL, CSV et XML, de l’historique, des captures et des vidéos.

Un test a détecté une confusion entre Markdown et SQL lorsque la requête contenait `**texte**`. L’ordre de reconnaissance a été corrigé.

## Réactivité et limites

Les calculs sont annulables et exécutés en arrière-plan, avec un délai de 250 ms pendant la saisie. Foundation termine son appel d’analyse avant que l’annulation soit vérifiée ; les entrées de cet appel sont donc bornées à 128 Kio.

Le rendu conserve au maximum 1 000 blocs, 4 000 segments de style et 32 colonnes par tableau. Il signale un aperçu abrégé. L’édition reste limitée à 128 Kio ; la copie et l’export conservent le source complet. La limite générale de traitement reste de 4 Mio, avec accès à Original au-delà.

Mesures indicatives en Release sur le Mac Apple Silicon de développement :

| Mesure | Résultat observé |
| --- | --- |
| Styles natifs, 1 000 blocs et 4 000 segments | environ 11 ms |
| Styles natifs, tableau de 1 000 cellules | environ 9 ms |
| Mise en page de la première zone visible | environ 3 à 4 ms |
| Intervalle maximal du thread principal pendant une analyse volumineuse | environ 6 ms |
| Quatre entrées répétitives ou profondément imbriquées | environ 0,38 s au total, en arrière-plan |

Ces mesures ne constituent pas une garantie pour toutes les machines et tous les contenus. Les clics physiques, VoiceOver et l’exécution sur Mac Intel restent à vérifier. Le Markdown est un aperçu du texte, sans exécution HTML, téléchargement d’images, conversion HTML ou copie enrichie. Ce n’est pas un éditeur WYSIWYG.

## Reproduire

Depuis `app/EasyPaste` :

```sh
swift test -j 2 -c release
EASYPASTE_LAYOUT_SNAPSHOTS="$PWD/.build/markdown-snapshots" swift test -j 2 -c release --filter 'Markdown|Structured'
```
