# EasyPaste 0.3.11 — validation

Date : 3 novembre 2026. Build : 32.

## Périmètre

- Ajout de l’action OCR au premier niveau du menu de la barre des menus.
- Ajout d’un bouton `text.viewfinder` de 42 × 42 points entre Capture et Réglages dans la barre rapide.
- Réutilisation du circuit de capture existant : fermeture de l’interface avant sélection, extraction locale et ajout à l’historique.
- Infobulle avec raccourci personnalisé, libellé d’accessibilité et désactivation pendant les opérations incompatibles.
- Le routage de la molette validé et publié en 0.3.10.2 n’a pas été modifié.

## Vérifications

- Compilation Release avec SDK déclaré 27.0 et cible minimale macOS 15.
- 18 tests ciblés (raccourcis et interactions de la barre) : aucun échec.
- Suite complète : 338 tests, aucun échec, 55,921 secondes.
- `git diff --check` : aucun problème.
- Relecture du branchement du menu : action et tag OCR, validation existante et actualisation du raccourci personnalisé.
- Relecture du bouton : toute la surface est cliquable via `FullAreaButtonStyle`, couleurs et transparence issues du thème existant.

Les nouveaux accès n’ont pas fait l’objet d’un essai manuel de capture à cette étape. Les tests d’interaction automatisés ne remplacent pas un geste réel de souris ; aucune nouvelle validation physique de la molette n’est revendiquée.

Le paquet public doit passer la signature Developer ID, la notarisation Apple et la vérification des téléchargements et du flux signé avant publication effective.
