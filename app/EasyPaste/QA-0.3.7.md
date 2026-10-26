# Validation EasyPaste 0.3.7

26 octobre 2026. Livraison préparée depuis `codex/reprise-easypaste-2026-10-24`, après autorisation de publication par Hervé.

## Vérifications de cette livraison

- Suite Mac Debug : **287 tests, zéro échec**, 37,75 s.
- Suite Mac Release : **287 tests, zéro échec**, 34,69 s.
- Extension navigateur : **60 tests JavaScript, zéro échec**.
- Parité des sept fichiers d’annotation partagés avec EasyShoot : conforme.
- Vérification des différences Git : aucune erreur d’espacement.
- Compilation et préparation des archives sur le SSD interne ; deux tâches de compilation au maximum.

Les suites couvrent notamment l’ancrage de la barre, les clics, les dimensions et le remplacement des images, les titres de tuiles, le cache d’icônes, l’extraction de l’origine web, les formats de texte, les SVG et le protocole natif du navigateur. Elles ne constituent pas un essai manuel de chaque fonctionnalité ni une mesure du rendu sur tous les Macs.

## Essais réels antérieurs à cette livraison

Le journal complet est dans `docs/reprise/EASYPASTE-REPRISE-2026-10-24.md`, à la racine du dépôt. Il conserve les preuves des essais réels : capture, annotation et remplacement d’image, vidéo avec lecture et déplacement dans la piste, copie de page avec mise en forme dans Arc, lien natif et plusieurs cycles d’ouverture de l’aperçu sur des tuiles image et texte.

Hervé a confirmé le 24 octobre que la barre reste fixe au clic sur l’œil après le correctif `b521f0c`. Cette confirmation est sa validation du mouvement perçu, distincte des tests de géométrie automatisés.

## Limites de couverture

L’exécution sur Intel, les autres versions de macOS, toutes les combinaisons de thèmes et d’accessibilité, les scénarios YouTube réels et l’ensemble des combinaisons webcam/micro/audio système n’ont pas été rejoués pour cette livraison. Les échanges Bitwarden réels et une installation OTA complète depuis une ancienne version ne sont pas déclarés retestés dans cette session.

Les notes de version ont été relues manuellement. Le contrôleur de rédaction optionnel ne démarre pas, car sa dépendance spaCy 3.8.14 est absente ; aucune dépendance n’a été ajoutée pour ce contrôle.

La version et le build destinés à la distribution sont **0.3.7 (24)**, avec l’identifiant `app.easypaste.mac` et le certificat Developer ID « Les papas du code » existants. 

## Paquet de distribution

- Exécutable universel : arm64 et x86_64, minimum macOS 15.0, SDK déclaré 27.0.
- Application et DMG signés ; contrôles `codesign --verify --deep --strict` et Gatekeeper acceptés.
- Notarisation Apple acceptée : `b4aee7cc-51b2-4b3f-a79e-dcd9cfd4afae`. Tickets agrafés au DMG et à l’application de l’archive ZIP.
- Identifiant, clé publique Sparkle et options de vérification du flux conservés ; aucun marqueur Demo, UpdateQA ou AnnotationPreview dans le paquet.
- Fichiers d’exécution de l’extension inclus et comparés aux sources ; aucune dépendance de test embarquée.
- Trame native invalide soumise au binaire distribué : sortie propre sans réponse ni démarrage d’interface.

La publication utilise le script existant : signature Ed25519 du flux et du DMG, vérification locale avec la clé publique, téléversement d’un brouillon, téléchargement et comparaison SHA-256 de chaque fichier, puis publication et mise à jour du flux. La disponibilité publique doit être confirmée après déploiement de GitHub Pages.
