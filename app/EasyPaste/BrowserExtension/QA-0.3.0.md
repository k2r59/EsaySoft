# EasyPaste Web 0.3.0 : vérification du 20 novembre 2026

Rapport des essais locaux préparant EasyPaste 0.3.14. L’extension n’est pas publiée sur le Chrome Web Store.

## Sous-titres dans un vrai navigateur

Chrome for Testing, profil temporaire indépendant, extension chargée avec son manifeste de distribution inchangé. Activation réelle de son action via CDP, autorisation `activeTab`, exécution dans les contextes MAIN et ISOLATED. Ce test isolé ne modifie aucun profil utilisateur. Des essais manuels complémentaires ont ensuite été faits dans Arc, avec l’extension locale installée à la demande de l’utilisateur.

Vidéo `0e3GPea1Tyg` :

| Piste | Passages récupérés | Résultat |
| --- | ---: | --- |
| Français | 805 | Aperçu complet reçu |
| Anglais manuel | 791 | Aperçu complet reçu |
| Japonais | 765 | Aperçu complet reçu |
| Italien | 903 | Aperçu complet reçu |
| Espagnol | 774 | Aperçu complet reçu |
| Anglais automatique | 654 | Aperçu complet reçu |
| Panneau natif YouTube | 697 | Lecture du panneau réussie |

Les langues du panneau natif et des pistes directes sont indépendantes. Les nombres ci-dessus proviennent des essais de cette session, pas des résultats annoncés dans le ZIP fourni.

Copie d’un aperçu modifié vérifiée dans le presse-papiers système : texte exact, format HTML présent, métadonnée de source YouTube conservée. Le droit de lecture du presse-papiers n’a été accordé qu’au profil de test, par CDP ; il n’est pas demandé dans le manifeste livré. Le menu final suit la maquette claire bleutée validée par l’utilisateur, même si le navigateur utilise un thème sombre.

## Téléchargements réels

Moteurs réutilisés depuis `/Applications/EasyMusic.app/Contents/Resources/bin`.

- MP4 direct hors YouTube : vidéo CC0 `flower.mp4` de MDN, analyse et téléchargement réussis.
- YouTube `jNQXAC9IVRw`, vidéo de 19 secondes : analyse, téléchargement MP4 et conversion MP3 réussis.
- Fichiers créés dans des dossiers temporaires de test, taille vérifiée, puis supprimés.

Le fonctionnement du moteur a été testé avec le même constructeur d’arguments que l’app. La transmission native et la file de tâches ont des tests dédiés avec des dossiers temporaires. Essai complet réalisé depuis Arc avec EasyPaste local 0.3.14 (39), signé Developer ID :
- ouverture du menu de l’extension, connexion vérifiée en vert ;
- choix Vidéo, puis clic sur Télécharger : attente puis téléchargement terminé ;
- choix Audio sans démarrage automatique, puis clic sur Télécharger : état téléchargement/conversion MP3 observé ;
- fermeture du popup pendant le parcours, réouverture : résultat terminé retrouvé ;
- sorties réelles vérifiées avec ffprobe : MP4 de 19,014 s (475 974 octets) et MP3 de 19,005 s (331 053 octets).

L’app ouvre sa fenêtre de suivi sans reprendre le focus du navigateur, afin que le popup reste utilisable. Les états viennent du moteur natif ; aucun faux pourcentage ou succès anticipé n’est affiché.

## Tests automatisés

- Extension : 81 tests Node/jsdom, tous réussis au moment de la préparation.
- Cas couverts : langue manuelle/automatique, piste absente ou vide, réponses trop volumineuses, URL de piste inattendue, navigation pendant chaque requête, texte modifié, horodatages, dédoublonnage, transcription filtrée, modèle virtualisé, copie refusée et source conservée.
- Médias : détection hors YouTube, choix de source, permission refusée, page changée, réponse native incorrecte ou expirée, URL non HTTP(S), origine d’extension inconnue, arguments bornés, playlists/DRM/directs refusés, annulation et délai maximal.
- App : tests de file de tâches, dossiers distincts, préservation des originaux, nettoyage après erreur, préparation/révocation du lien navigateur et mise en page à la taille minimale.

Le premier passage de la suite Mac a détecté des textes d’installation trop larges dans Réglages. Les textes ont été corrigés ; les tests de mise en page repassent. La suite complète Mac finale compte **373 tests réussis, zéro échec**. Les 11 tests médias ont aussi été relancés sur les dernières modifications, avec les deux essais réseau actifs, et passent.

## Reproduire

```sh
NODE_PATH="$HOME/Library/Caches/EasyPaste-extension-tests/node_modules" npm test
```

Le test navigateur optionnel est `tests/browser-smoke.mjs`. Il nécessite Playwright et une version récente de Chrome for Testing avec le domaine CDP `Extensions`. Définir `PLAYWRIGHT_MODULE` et `CHROMIUM_EXECUTABLE` si ces composants ne sont pas dans les chemins par défaut. `EASYPASTE_BROWSER_OUTPUT` choisit le dossier des captures. Il ouvre un profil temporaire et écrit une courte phrase d’essai dans le presse-papiers système.

Depuis la racine du dépôt :

```sh
EASYPASTE_MEDIA_LIVE_TEST=1 swift test \
  --package-path app/EasyPaste \
  --scratch-path "$HOME/Library/Caches/EasyPaste-build" -j 2
```

Sans la variable `EASYPASTE_MEDIA_LIVE_TEST`, les deux tests réseau de téléchargement sont ignorés. Ne pas lancer deux constructions Swift en parallèle sur le même cache.

## Limites vérifiées

Les fonctions de copie et de sous-titres sont autonomes. Les téléchargements nécessitent EasyPaste 0.3.14 et les moteurs décrits dans le README. Les versions 0.3.13 et antérieures ne reçoivent pas les nouvelles commandes. Aucun test ne garantit tous les sites compatibles yt-dlp, toutes les vidéos YouTube ou les sources nécessitant une authentification. L’extension utilisateur EasyPaste a été rechargée dans Arc ; les autres extensions n’ont pas été modifiées.

## Maquette et contrôle visuel

Trois écrans : accueil avec trois actions, sous-titres avec aperçu modifiable, téléchargement vidéo/audio et qualité. Connexion dans les réglages et statut discret dans le pied de fenêtre. Autres sources médias dans les réglages. États en attente, préparation, téléchargement, terminé, annulé, échec et suivi indisponible.

L’agent indépendant `extension_visual_qa` a relevé puis fait corriger un bouton coupé, le fond trop cyan et les coins supérieurs. Résultat final : **10/10 pour la qualité visuelle et fonctionnelle des trois écrans contrôlés**. Sa note de fidélité littérale à l’image générée reste **9/10** : format de popup360×600, logo officiel, données réelles et petites tailles adaptées. Ne pas déclarer «100% pixel identique».

Les captures `extension-home.png`, `extension-captions.png` et `extension-download.png` sont des rendus du DOM réel du popup dans une page séparée360×600, DPR2. Le popup natif headless est limité à498px par son écran virtuel et produit des tuiles répétées au-delà ; le test copie donc son DOM, ses valeurs de champs et ses CSS dans une page de rendu. Les interactions et copies sont testées sur le véritable popup. Une assertion vérifie que les CTA sont au-dessus du footer, sans débordement horizontal. Les vérifications Arc utilisent également l’arbre d’accessibilité réel.

Le suivi conserve seulement le dernier identifiant de tâche, son format et sa date dans le stockage local de l’extension. Les réponses natives sont limitées au job demandé, à la génération de connexion courante, à24h, et sans chemin de fichier. Les tests vérifient les nonces, les refus, les états incohérents, le changement de page, les options de qualité et l’absence de téléchargement à la simple sélection d’un format.
