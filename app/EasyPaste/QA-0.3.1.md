# Validation EasyPaste 0.3.1

20 octobre 2026, Mac Apple Silicon, macOS 27.

## Tests et interface

- Suite Release : **195 tests, aucun échec**, 24,36 s.
- Après correction de l’accessibilité des interrupteurs : 6 tests ciblés
  supplémentaires, aucun échec.
- Rendu des quatre rubriques à la largeur minimale disponible de 837 points.
- Essais natifs avec un historique de démonstration : les quatre onglets
  affichent leur rubrique ; le clic dans la marge de l’onglet fonctionne.
- Clic au milieu d’une ligne de réglage, hors texte et interrupteur : état changé.
  Recontrôlé après la correction d’accessibilité.
- Les interrupteurs apparaissent comme `commutateur`, avec état `on`/`off`,
  et répondent à leur action d’accessibilité native.
- Les deux sons originaux PCM sont courts (65 et 160 ms), non saturés et chargés
  par NSSound. Lecture des deux fichiers effectuée sur le Mac.
- Tests des préférences indépendantes, de leur persistance, du silence pendant
  l’enregistrement et d’une rafale de 100 demandes sans file d’attente.
- Le son de capture est déclenché après l’enregistrement de l’image ou du texte
  OCR ; sa copie automatique est silencieuse pour ne pas jouer deux sons.
  Le moteur de capture et d’OCR est inchangé.

## Distribution et mise à jour réelle

- Deux architectures présentes, `LC_BUILD_VERSION minos 15.0` sur Intel
  et Apple Silicon.
- Signature Developer ID et notarisation acceptée :
  `2631070f-8027-4ddc-9794-5bc0796b0120`.
- Archives téléversées sur GitHub, retéléchargées et comparées par SHA-256.
- Flux public GitHub Pages identique octet pour octet au flux signé ; vérification
  Ed25519 avec la clé publique.
- **Deuxième cycle OTA réel**, depuis l’installation 0.3.0 / build 17 :
  recherche, proposition de 0.3.1, téléchargement, extraction, installation,
  fermeture et relance automatique, sans relancer l’app avec un outil externe.
- Résultat installé : `/Applications/EasyPaste.app`, **0.3.1 / build 18**.
  `codesign --verify --deep --strict` et Gatekeeper valides après l’installation.
- Les **192 fichiers chiffrés** du coffre sont identiques avant et après.
- Dans la version installée : nouveaux réglages présents, deux sons activés,
  vérifications automatiques activées puis désactivées lors du test pour conserver
  le choix initial. La recherche suivante annonce que 0.3.1 est à jour.
- Vérification ponctuelle au repos, réglages ouverts : CPU 0,0 %, RSS environ
  162 Mio. Aucun processus de compilation ou de test laissé en exécution.

Les deux cycles sont documentés ici et dans `QA-0.3.0.md`. L’exécution Intel,
les autres versions de macOS et un second Mac ne sont pas validés matériellement
sur cette machine. Les versions 0.2.x nécessitent une dernière installation
manuelle du DMG.
