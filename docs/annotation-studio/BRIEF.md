# Atelier d’annotation — préversion locale

Demande : reproduire fidèlement la fenêtre Annotate / Background Tool de CleanShot X, pour EasyPaste et EasyShoot, en français. Référence fournie par l’utilisateur le 22 octobre 2026. Aucune publication ni modification du flux OTA avant validation personnelle. La demande initiale prévoyait des prototypes séparés ; la demande suivante autorise maintenant une mise à jour locale de l’EasyPaste installée, avec la même identité de signature et sans nouvelle copie visible.

Sources officielles consultées :
- https://cleanshot.com/features : outils d’annotation, fond personnalisé, marges, alignement, proportions, Auto Balance et préréglages.
- https://cleanshot.com/changelog : réglages numériques et préréglages du Background Tool.

Structure de la référence : barre d’outils compacte en haut, inspecteur contextuel unique à gauche, grande surface centrale, zoom et actions en bas. Visuels de fond propres au projet ; aucun fond ou asset propriétaire extrait de CleanShot. Aucun bouton d’envoi Cloud simulé.

Tests utilisateurs : bundles AnnotationPreview dédiés. L’entrée de prévisualisation s’exécute avant les délégués de production. Aucun historique, service de capture, compte Bitwarden, serveur MCP, login item ou updater de production n’est initialisé. Import manuel d’une image, annotation, composition, copie/export local.

Guides UI/UX : recherche SwiftUI toolbar/inspector sans résultat ; recherche UX keyboard toolbar controls pertinente pour focus visible et ordre clavier. Les règles mobiles de taille ne sont pas transposées aveuglément à cette barre d’outils macOS compacte.

## Ajustement demandé pendant l’essai

Le premier prototype était trop petit sur l’écran de l’utilisateur. Libellés portés à 12–13 points, icônes à 15 points dans des boutons de 34 × 32 points, palettes de 36 points, panneau gauche de 280 points. Les positions et groupes de la référence sont conservés. Fenêtre initiale : 1180 × 840 points, minimum 1080 × 700 ; l’inspecteur défile sur les petits écrans.

## Validation locale

- Suite complète EasyPaste : 224 tests réussis avant les derniers contrôles ciblés ; 2 tests d’annotation supplémentaires ensuite.
- Contrôles ciblés finaux : qualité sans rééchantillonnage, recadrage asymétrique, orientation EXIF, ombre/marges/proportions, arrondis, masquage opaque, annulation/rétablissement, export via glisser-déposer, tailles extrêmes, dessin des flèches.
- EasyShoot : la même suite de 11 tests du fond est ajoutée aux 19 tests existants.
- Vérification de la fenêtre en clair et sombre à sa largeur minimum ; essai manuel du fond, du format 16:9, d’une flèche, annuler/rétablir, enregistrer PNG et fermer.
- PNG issu du véritable bouton Enregistrer inspecté visuellement : 1316 × 740 pixels, original 620 × 340 conservé dans la composition.
- Simulation de 31 changements de marge : un seul pas d’annulation ; pas de reconstruction d’un bitmap de sortie 4K par l’application à chaque mouvement. Le banc de capture bitmap hors écran a pris environ 1,2 s pour ces 31 rendus Retina ; cette mesure inclut la capture AppKit et ne constitue pas une garantie de 60 images/s à l’écran.

Les deux produits embarquent les mêmes sept fichiers d’éditeur afin que leurs archives sources restent autonomes. Après modification : `python3 scripts/check-annotation-parity.py` vérifie leur identité. Les anciens prototypes isolés peuvent être préparés avec `scripts/build-annotation-preview.py EasyPaste` ou `EasyShoot`, mais l’essai actuel utilise directement l’EasyPaste installée, sans créer de nouvelle copie visible.

Les essais sont destinés à ce Mac Apple Silicon, macOS 15+. Aucun DMG public, notarisation, tag, publication, push ou modification du flux OTA n’a été effectué.

## Essai intégré dans EasyPaste

À la demande de l’utilisateur, les ajustements suivants sont intégrés localement : tuiles sélectionnées au simple clic et collées au double-clic, aperçu conditionnel, favoris et corbeille en pied de carte. Toutes les entrées de suppression récupérable passent par une confirmation commune, désactivable et réactivable dans les réglages. La suppression définitive conserve sa confirmation distincte.

La barre rapide utilise une seule surface Liquid Glass sur macOS 26+, un matériau natif sur macOS 15 et un fond opaque si la transparence est réduite ou le contraste augmenté. Les cartes restent opaques. Les contenus et les aperçus ne sont pas rééchantillonnés pour cet effet. Aucun délai n’est ajouté à la sélection au simple clic.

La compilation et les tests utilisent le disque interne. L’application installée conserve `app.easypaste.mac` et l’équipe de signature existante ; aucune réinitialisation d’autorisation. Aucun tag, push, DMG public ou changement d’appcast pendant cet essai.

### Contrôles de l’intégration des tuiles — 22 octobre 2026

- 233 tests EasyPaste réussis (suite complète), dont sélection immédiate, double-clic, modificateurs clavier, favoris, confirmation/annulation/suppression désactivable, suppression multiple et restauration.
- Captures de disposition en clair/sombre : barre normale et compacte, cartes, liste, fond opaque, bibliothèque, réglages et éditeur à largeur minimum.
- Build universel arm64/x86_64, minimum macOS 15 ; signature Developer ID vérifiée et exigence désignée identique à l’installation précédente.
- Même version de distribution 0.3.5 (22) pendant cet essai privé : aucun changement de release.json ou d’appcast.
- Application remplacée localement et relancée. Signature vérifiée après installation ; aucun changement d’identifiant ni de droit d’accès.
- Essais dans l’app : sélection au simple clic, déclenchement du collage au double-clic, aperçu, ajout/retrait des favoris, annulation et validation de la confirmation de suppression. Seule la carte créée pour ces essais a été déplacée dans la corbeille. L’outil de contrôle maintenait ChatGPT comme application cible ; le collage effectif dans TextEdit n’est donc pas déclaré validé.

### Liquid Glass dans l’application

La barre latérale, la recherche, la navigation des réglages et les barres d’outils utilisent un matériau commun. Les tuiles, champs de saisie, images et surfaces de lecture restent opaques. Le fond est statique ; aucun shader animé, minuteur ou matériau par tuile n’est ajouté. Le mode réduit en transparence ou augmenté en contraste emploie un fond opaque.

### Intégration locale du 22 octobre 2026 — en validation

- L’aperçu de la barre est intégré au même panneau : silhouette en T inversé, bord inférieur fixe, fermeture de l’aperçu avant celle de la barre avec Échap. Décodage et formatage hors du fil principal ; les chargements obsolètes sont annulés, le lecteur vidéo est libéré à la fermeture.
- Les icônes des cartes mesurent 13 points dans des cibles de 30 points ; la corbeille est rouge. Les nouvelles copies réinitialisent la sélection ; simple clic pour sélectionner, double-clic pour coller.
- Le collage fige son application destinataire à l’ouverture. Un changement volontaire vers une autre app pendant l’opération annule le collage automatique au lieu d’y envoyer le contenu.
- L’URL d’origine est une métadonnée facultative, compatible avec les anciens historiques. La balise `easypaste-source-url` de l’extension est prioritaire, puis `org.chromium.source-url`, puis une lecture bornée de l’Accessibilité du navigateur. Aucun script injecté, requête réseau ou nouvelle permission. Seules les URL HTTP(S), sans identifiants intégrés, peuvent être ouvertes par le globe de la carte. Un lien présent dans le contenu n’est jamais pris pour l’URL de sa page.
- Les captures d’une zone incluse dans la fenêtre du navigateur conservent la source seulement si la page et la géométrie restent identiques ; les captures d’une autre fenêtre n’héritent pas de cette URL. Les annotations et le stockage chiffré la conservent, sans ajouter le lien au texte collé.
- Extension 0.1.2 : 47 tests et copies réelles dans Chrome d’une page formatée et d’une transcription YouTube (377 passages). ZIP dans `~/Downloads/EasyPaste-Web-0.1.2.zip`.
- 253 tests EasyPaste réussis sur l’intégration complète, puis 18 tests ciblés réussis après le dernier garde de provenance des captures de fenêtre et le test de conservation de la source lors des annotations. Contrôle visuel en attente de disponibilité de la souris et du clavier.
- Retour utilisateur : le matériau Regular était trop blanc/opaque. La barre passe au matériau Apple Clear. Le script de compilation déclare maintenant le SDK réellement utilisé tout en conservant macOS 15 comme minimum ; le binaire précédent déclarait incorrectement SDK 15. Le rendu réel doit être vérifié avant validation, sans assimiler les captures de tests hors écran au résultat du compositeur macOS.

Cette itération reste privée : aucun commit publié, aucune release, aucun flux OTA modifié. EasyPaste conserve le même bundle, la même identité de signature et son historique.

- Vérification visuelle après installation : bibliothèque claire, réglages sombres et retour au thème clair initial.
- 233 tests EasyPaste réussis après ces changements, puis un test supplémentaire de transport HTML : lecture d’un presse-papiers isolé, stockage chiffré, récupération exacte de la mise en forme et copie en texte brut sans altérer l’original.
- 30 tests EasyShoot réussis et parité des sept fichiers partagés vérifiée. EasyShoot n’a pas été réinstallée ni publiée.
- Observation ponctuelle d’EasyPaste au repos : 0 % de CPU et environ 170 Mo de mémoire résidente. Ce relevé n’est pas une garantie de performance pour toutes les machines ou tous les historiques.
- Extension Chrome préparée séparément dans `app/EasyPaste/BrowserExtension` : 32 tests réussis et copie riche vérifiée dans Chrome sur une page de test. Le ZIP local se trouve sur le Bureau : `EasyPaste-Web-0.1.0.zip`. Les essais intégrés de l’extension et de YouTube nécessitant son installation restent soumis à la validation de l’utilisateur ; aucun accès au navigateur n’est accordé silencieusement. La carte créée par la copie de test Chrome a été déplacée dans la corbeille.


### État actuel de l’essai Liquid Glass — 22 octobre 2026, révision 8

Cette section remplace les valeurs des essais précédents ci-dessus. La version locale conserve 0.3.5 (22), le bundle app.easypaste.mac et la signature Developer ID Les papas du code. Aucun flux de mise à jour, archive de diffusion, tag ou dépôt distant n’a été modifié.

- Barre de 320 points (270 en mode compact), aperçu intégré jusqu’à 600 points et largeur 49,5 % de la barre, coins 36 points et raccords concaves de 58 points. La place de l’annulation et des sélections multiples est réservée uniquement lorsqu’elle est nécessaire.
- Matériau natif Apple Regular sur macOS 26+, voile bleu/aqua statique et double liseré blanc. Le passage expérimental à Clear a été abandonné après comparaison réelle. Repli natif sur macOS 15 ; fond opaque pour les réglages d’accessibilité.
- Cartes 252 × 215 points, titres de type et âge, texte 15 points, commandes de 16 points dans des cibles de 30 points. Le nom de l’application source reste accessible via l’infobulle et l’Accessibilité. Aucun minuteur supplémentaire par carte.
- Actions d’aperçu de 54 points ; boutons Capture et Réglages de 42 points. Capture utilise un bouton AppKit : SwiftUI réduisait son image personnalisée. Le menu conserve les cinq commandes de capture et l’arrêt de l’enregistrement. Clic dans la marge vérifié.
- Transparence réglable de 0 à 80 %, valeur initiale 45 %. Les cartes restent opaques. Le mode sombre maintient un voile minimum pour garantir la lisibilité même sur fond blanc ; capture à 80 % examinée par le contrôleur indépendant.
- Suite complète finale : 258 tests réussis, 37 secondes, journal interne `/tmp/easypaste-glass-revision8-full-tests.log`. Les tests de contraste composent les couleurs réellement utilisées par les cartes, les commandes et l’onglet actif, en clair/sombre et sur fonds blanc/noir. Tests de taille minimum, mode compact, pied de barre conditionnel et repli d’accessibilité réussis.
- Compilation universelle arm64/x86_64 sur le SSD interne, minimum macOS 15, SDK 27 ; signature vérifiée après remplacement atomique de l’application. Les sauvegardes de la version précédente sont conservées sur le SSD interne.
- Contrôle indépendant visuel : progression de 5,5/10 à 9,2/10. La note est une appréciation du rendu, pas une mesure de pixels identiques. Ne pas annoncer une reproduction à 100 % : la lumière dépend aussi du bureau sous le matériau natif, et des détails de glyphes restent différents.
- Preuve de la révision 8 : `/Users/k2r59/Library/Caches/EasyPaste-visual-review/revision-8.jpg`. Le fichier `older-desktop-1902-not-revision8.png` est une ancienne capture récupérée par erreur dans Aperçu : il ne valide pas la révision 8. Les dialogues système empêchent encore une comparaison propre du bureau complet ; aucune interaction avec ces dialogues n’est contournée.

L’installation locale est prête pour l’essai visuel. Le contrôle de collage effectif dans TextEdit reste non conclusif ; les tests de destination et de transport du presse-papiers passent. Aucune affirmation de fonctionnement sans bug ni d’identité pixel par pixel.


### Révision 9 — affinage demandé par le contrôle visuel

Le voile blanc diagonal a été réduit (pics 0,42 / 0,12 / 0,10) pour laisser ressortir le bleu ; les reflets forts restent sur le contour. Un filet bleu de 0,7 point, à 2,7 points du bord, sépare les deux liserés en mode clair. Pictogrammes rapprochés de la référence : horloge simple, capture dans l’entête, feuille de texte sur les cartes et deux feuillets verticaux dessinés en vecteur sur Coller. Le vert du bouton reste légèrement plus sombre pour le contraste.

Les sept tests ciblés de disposition et de contraste passent après ces changements ; les 258 tests de la révision précédente restent le dernier passage complet. La navigation réelle sur treize cartes au clavier, puis l’ouverture de l’aperçu, a été vérifiée. Capture actuelle : `/Users/k2r59/Library/Caches/EasyPaste-visual-review/revision-9.jpg`. Le même bundle a été remplacé localement ; signature et minimum macOS 15 vérifiés pour arm64 et x86_64. Aucun envoi externe.


### Révision 10 — dernier détail local

Le bouton Coller reçoit un contour turquoise de 1,25 point en clair ; sa couleur de fond et son contraste restent inchangés. Capture authentique : `/Users/k2r59/Library/Caches/EasyPaste-visual-review/revision-10.jpg`. Compilation universelle et signature vérifiées, même installation privée. La note de fidélité reste provisoire tant que la comparaison composée sur le bureau n’est pas terminée. Le signal sonore de fin n’a pas été joué : la validation demandée à 10/10 reste ouverte.
