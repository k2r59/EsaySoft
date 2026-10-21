# Validation EasyPaste 0.3.2

21 octobre 2026, Mac Apple Silicon, macOS 27.

## Apparence

- Clair par défaut en l’absence de préférence, y compris pour les utilisateurs existants.
- Choix Clair / Sombre / Automatique conservé dans les préférences locales.
- Automatique retire la surcharge d’apparence de l’application et suit macOS.
- Palette dynamique commune à SwiftUI et AppKit ; aucune relecture du coffre,
  aucun nouveau timer et aucun décodage d’image déclenchés par ce réglage.
- Thèmes imposés retirés de l’historique, de la barre rapide, des réglages,
  des éditeurs, de l’annotation, des fenêtres Bitwarden, de la pipette et de la vidéo.
- Le document enrichi conserve sa feuille blanche et ses couleurs d’origine.
  Les photos, SVG, couleurs échantillonnées et annotations exportées ne sont pas recolorés.

## Vérifications

- Suite Release : **200 tests, aucun échec**, 24,67 s.
- Tests ciblés : valeur initiale, préférence invalide, trois choix persistants,
  héritage des fenêtres, suppression de la surcharge en mode automatique.
- Contraste des textes et accents sur les trois surfaces, dans les deux thèmes :
  au moins 4,5:1 ; contrôle séparé des libellés sur les boutons principaux.
- Couleurs SwiftUI converties en NSColor : adaptation vérifiée après leur création,
  pour les éditeurs natifs conservés en mémoire.
- Rendus clair/sombre aux largeurs minimales pour l’historique, l’annotation et
  les quatre rubriques de réglages.
- Essai natif avec historique fictif : clair au premier lancement, passage immédiat
  au sombre, puis automatique correspondant au macOS sombre de ce Mac.
- Historique et réglages inspectés visuellement dans les deux thèmes.

## Autorisation de capture

L’utilisateur a vu la fenêtre d’aide à l’autorisation durant les essais.
Le journal TCC identifie une demande de la copie de test séparée
`app.easypaste.theme-qa`, qui a ensuite été fermée. La version installée
`app.easypaste.mac` a été vérifiée : le bouton Capturer une zone ouvre la sélection
sans afficher de nouvelle demande. Sélection annulée sans enregistrer d’image.
Aucune autorisation de l’application installée n’a été réinitialisée.

## Compatibilité

Les deux exécutables arm64 et x86_64 ciblent macOS 15.0. L’exécution Intel et
les autres versions de macOS ne sont pas vérifiées matériellement sur ce Mac.

## Distribution et installation

- Application et DMG signés Developer ID, notarisés et agrafés.
  Notarisation : `150572a2-898c-4ab5-95bd-61e3b000be48`.
- Installation locale **0.3.2 / build 19** dans `/Applications/EasyPaste.app`.
  Gatekeeper confirme `Notarized Developer ID`.
- Identifiant et exigence de signature identiques à 0.3.1 : `app.easypaste.mac`,
  équipe `WN9MHL56A9`.
- Les **225 éléments chiffrés existants** sont identiques avant et après installation.
- Premier lancement de la version signée : apparence claire. Les trois choix
  répondent immédiatement dans les réglages ; le mode clair est laissé actif.
- La nouvelle version ouvre la sélection de capture sans nouvelle autorisation.
  L’essai est annulé sans enregistrer d’image.
