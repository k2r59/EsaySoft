# Validation EasyPaste 0.3.0

20 octobre 2026, Mac Apple Silicon, macOS 27.

- Suite Release : 191 tests, aucun échec, 24,20 s.
- 5 tests de report d’installation, activités bloquantes et absence de requête
  réseau avant le démarrage explicite de l’updater.
- Build universel Intel/Apple Silicon ; signature Developer ID de l’application,
  du framework Sparkle et de ses services ; notarisation Apple acceptée
  (`fd52b5ff-9812-47f8-8cc2-5229f4d298be`).
- Application de départ également signée et notarisée, build 16.
- Première recherche avec le flux absent : erreur native en français, retour
  normal dans l’app. Aucun remplacement de fichier.
- Flux GitHub Pages téléchargé et comparé octet pour octet au flux signé.
- Signature Ed25519 du flux et du DMG vérifiée avec CryptoKit et la clé publique.
  Flux modifié et DMG modifié d’un octet : tous deux rejetés.
- Cycle réel par l’interface Sparkle : découverte de 0.3.0, téléchargement du DMG
  GitHub de 9,4 Mo, préparation, « Installer et relancer », remplacement de
  `/Applications/EasyPaste.app`, relance automatique constatée sans commande
  externe de lancement.
- Version finale 0.3.0 / build 17 ; vérifications `codesign --deep --strict`
  et Gatekeeper positives après l’installation.
- Les 192 fichiers chiffrés préexistants du coffre sont identiques après le cycle.
- Nouvelle recherche : « EasyPaste 0.3.0 est la version la plus récente disponible ».
- Ancienne application conservée dans les sauvegardes locales.

L’exécution Intel et les autres versions de macOS ne sont pas testées sur ce Mac.
Les versions 0.2.x nécessitent une dernière installation manuelle du DMG.
