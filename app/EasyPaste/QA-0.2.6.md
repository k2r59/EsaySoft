# EasyPaste 0.2.6 : JSON, SQL, CSV et XML

Version 0.2.6, build 11. Traitement local, sans dépendance externe supplémentaire. La licence MIT reste inchangée.

## Comportement

Les cartes reconnaissent les formats probables avec une analyse bornée et un cache. Le formatage de l’aperçu s’exécute en arrière-plan. **Formater…** ouvre un éditeur commun avec copie, création d’une variante, remplacement confirmé et export. Les variantes sont regroupées avec leur original. La présentation seule ne modifie ni le contenu enregistré ni le comportement du double-clic.

JSON utilise un analyseur lexical qui conserve les nombres, leur notation, les échappements, l’ordre des champs et les clés répétées. Le formatage ne passe pas par une conversion en nombres flottants. CSV respecte les cellules citées, les guillemets doublés, les retours internes, les cellules vides et les zéros initiaux. Le tableau natif charge les cellules visibles à la demande. XML conserve les balises et leur contenu, protège les espaces existants, le contenu mixte et CDATA. Les DTD sont refusées par le formatage et les entités externes sont désactivées.

SQL utilise une mise en page conservatrice. Les dialectes Standard, PostgreSQL, MySQL, SQLite et SQL Server déterminent le traitement des chaînes et commentaires. Le moteur repère les chaînes, commentaires et parenthèses non fermés. Il ne valide pas toute la grammaire SQL. Aucune requête n’est exécutée.

## Essais du 19 octobre 2026

Les tests utilisent des historiques temporaires chiffrés et des presse-papiers nommés. Ils ne remplacent pas l’historique personnel.

La suite finale comprend 99 tests, dont 40 consacrés aux nouveaux formats et à leur intégration. Deux exécutions complètes de cette suite en Release passent sans échec avant la fabrication de l’installateur. Une passe précédente de 98 tests passait également avant l’ajout du contrôle de libération des éditeurs.

- Cas de référence JSON, SQL, CSV et XML, formatage répété, Unicode et conservation des valeurs.
- 150 objets JSON générés et tableaux CSV générés avec les quatre séparateurs.
- 465 variantes tronquées, avec caractères supprimés ou guillemets substitués. Les 321 cas refusés renvoient une erreur ; les autres peuvent encore former un document valide ou une suite de jetons SQL. Chaque sortie acceptée est retraitée.
- Erreurs JSON localisées, CSV incohérent ou non fermé, XML invalide, DTD et imbrication excessive, chaînes et commentaires SQL non fermés.
- Correction d’une entrée invalide dans chaque format. Copie et enregistrement refusés tant que l’éditeur signale une erreur ; la vue Original reste accessible.
- Copie complète malgré un aperçu tronqué, recherche CSV sans perte de lignes à l’export, édition d’une cellule conservant `00123`.
- Enregistrement chiffré, variante adjacente, conservation des métadonnées lors d’un remplacement, refus d’un original périmé ou supprimé, modification concurrente d’un favori.
- Annulation des calculs, changements rapides de format et de présentation, fermeture répétée des éditeurs et libération des modèles.
- Éditeurs AppKit natifs : saisie, annulation/rétablissement, navigation vers une erreur et barre de recherche. Rendus hors écran inspectés à 690 × 570 pour les quatre formats.

Ces essais ont détecté un défaut d’actualisation après l’annulation native. La synchronisation de l’éditeur écoute maintenant les notifications d’annulation et de rétablissement ; la coloration ne pollue pas l’historique d’annulation.

## Mesures de réactivité

Mesures indicatives en Release sur le Mac Apple Silicon de développement, obtenues avec des données synthétiques :

| Cas | Taille | Durée observée |
| --- | --- | --- |
| JSON | 576 001 octets | environ 1 à 2 ms |
| CSV | 20 000 lignes de données, 297 786 octets | environ 6 à 7 ms |
| XML | 6 000 éléments, 240 007 octets | environ 31 à 35 ms |
| Reconnaissance de cartes JSON | 10 000 cartes | environ 7 à 11 ms |

Le contrôle de réactivité du thread principal pendant un formatage JSON volumineux mesure un intervalle maximal d’environ 6 ms. Ces chiffres mesurent les chemins testés ; ils ne garantissent pas la même latence pour tout document ou toute machine.

L’entrée de formatage est limitée à 4 Mio, le résultat à 8 Mio et l’imbrication à 128 niveaux. L’aperçu textuel et sa recherche sont limités à 128 Kio ; la coloration porte sur les 64 premiers Kio. Le tableau accepte 256 colonnes et 200 000 cellules, avec une limite de 16 Kio par cellule affichée ou éditable. La copie et l’export conservent les valeurs complètes. La structure XML présente au maximum 2 000 balises. Ces limites sont documentées dans le guide et indiquées dans l’interface lorsqu’elles s’appliquent.

## Reproduire les tests

Depuis `app/EasyPaste` :

```sh
swift test -j 2 -c release
EASYPASTE_LAYOUT_SNAPSHOTS="$PWD/.build/structured-snapshots" swift test -j 2 -c release --filter Structured
```

## Limites de la validation

Les parcours natifs sont exercés par les tests sur des vues réelles hors écran. Le contrôle interactif du bureau n’était pas disponible : les clics physiques, la navigation VoiceOver et l’export via le panneau système ne sont pas certifiés par cette passe. Les moteurs de capture et de vidéo n’ont pas été modifiés ; leurs tests de régression restent inclus. L’exécution sur un Mac Intel reste à vérifier.

Le correcteur rédactionnel automatique n’a pas pu démarrer, car spaCy 3.8.14 n’est pas installé. Le guide et ce rapport ont été relus manuellement.

Les références de syntaxe sont [RFC 8259 pour JSON](https://www.rfc-editor.org/rfc/rfc8259), [RFC 4180 pour CSV](https://www.rfc-editor.org/rfc/rfc4180) et [XML 1.0](https://www.w3.org/TR/xml/). Les variantes CSV avec point-virgule, tabulation et barre verticale sont aussi prises en charge.
