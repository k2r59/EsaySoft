# Plan de contrôle — EasyMusic 0.5.0, lecture en streaming

Cette demande modifie le comportement du bouton Lire avant publication. Les trois suites à 94 tests et l’audit précédent décrivent la version qui préparait un fichier local avant lecture ; ils ne valident pas encore le nouveau comportement. Publication suspendue jusqu’aux tests de la nouvelle implémentation.

## Contrat attendu

Lire un morceau distant doit résoudre puis lire un flux audio complet, sans l’ajouter à la bibliothèque locale et sans lancer la file des téléchargements. Le téléchargement reste une action explicite et indépendante. Un morceau local reste lu depuis son fichier. La pré-écoute reste distincte et limitée à trente secondes.

## Scénarios et preuves attendues

| # | Scénario | Assertions automatisées | Observation réelle/UI |
|---|---|---|---|
| 1 | Lire un titre distant | Résolution appelée une fois ; zéro appel downloadWorker ; aucune entrée locale/pending/activeDownloads ; état courant correct. | Démarrage du morceau, progression réelle ; icône de téléchargement toujours disponible. |
| 2 | Lire un titre déjà local | Résolution réseau non appelée ; fichier local prioritaire ; autre clic pause/reprise sans résolution. | Lecture locale, icône déjà téléchargé conservée. |
| 3 | Préparation et clics concurrents | A puis B, résolution A tardive ignorée ; second clic annule ; extrait/autre titre/local invalide l’ancien identifiant ; tâche de résolution interrompue si prise en charge. | Le titre affiché correspond au son ; aucun démarrage différé après annulation. |
| 4 | Streaming complet versus extrait | Le streaming ne s’arrête pas à30s ; l’extrait s’arrête à30s maximum ; transition extrait→stream sans état ni durée obsolète. | Progression au-delà30s, extrait distinct ; seek utilisable selon la source. |
| 5 | Téléchargement indépendant | Enqueue explicite pendant streaming conserve l’item AVPlayer et sa position ; fin du download n’interrompt/rejoue pas le flux ; pas d’auto-download de tout le contexte. | Coexistence lecteur et progression téléchargement, puis coche locale. |
| 6 | Commandes et file mixte | Queue de Track locaux/distants ; suivant/précédent, fin de file, repeat1/file, shuffle puis restauration ordre ; item terminé obsolète ignoré. | Lecture depuis la file ; commandes restent accessibles en streaming. |
| 7 | Source indisponible/protégée | Source directe échoue→autre source ; matching strict titre/artiste/version/durée ; audio uniquement ; nombre de tentatives borné ; aucune source protégée forcée. | Message concis ; bonne version jouée ou erreur explicite sans mauvais morceau. |
| 8 | Flux expiré ou illisible | Échec AVPlayer déclenche rafraîchissement/fallback borné ; résultat tardif ignoré ; absence de boucle ; annulation conserve absence de lecture. | Reprise ou erreur utilisable, pas de chargement permanent. |
| 9 | État et erreurs | Chargement libéré à chaque sortie ; pas de downloadErrors pour simple erreur streaming ; notice sans référence à un fichier inexistant ; durée/progression réinitialisées. | Play/pause/chargement cohérents dans ligne, fiche, lecteur, vue agrandie. |
| 10 | Persistance et ressources | Aucun fichier musical persistant créé pour streaming ; historique après10s réels ; mise à jour bloquée pendant résolution/lecture ; callbacks filtrés sur l’item courant. | Bibliothèque inchangée après écoute ; comportement lors d’un changement de page. |

## Organisation des tests

- Tests déterministes isolés via injection du résolveur de flux et du downloader, sans dépendance au réseau. Attendre l’API finale pour écrire ces tests.
- Tests de média sur au moins YouTube et SoundCloud disponibles, plus le titre Renaud signalé : résolution d’un flux lisible par AVFoundation, audio seul, position qui avance ; aucune sauvegarde dans le dossier musical de la fixture.
- Répéter les scénarios critiques puis les suites finales deux à trois fois ; conserver logs séparés et temps de début/fin.
- Binaire QA isolé neuf, compilé après les modifications ; vérifier contrôle visuel et résultat sur ce binaire. Les précédentes captures ne valent pas preuve pour les nouveaux états streaming.

## Points d’intégration à revoir

Le code antérieur relie `requestPlayback` à `enqueue`, puis `download` au lancement automatique. La file de lecture et les contrôles reposent sur `LocalTrack` et `playing != nil`. La personnalisation ne connaît que `playing?.track ?? previewing`. Le message d’échec AVPlayer référence un fichier dans le Finder. L’observateur de fin reçoit tous les items (`object:nil`) et doit ignorer ceux qui ne sont pas l’item courant. Ces couplages sont les zones de régression prioritaires.
