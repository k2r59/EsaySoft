# Validation EasyPaste 0.3.8

28 octobre 2026. Publication autorisée par Hervé, incluant le compteur de collages et les correctifs de recherche et de défilement. Version 0.3.8, build 25, branche `codex/reprise-easypaste-2026-10-24`.

## Tests

- Suite Mac Release relancée pour la livraison : **304 tests, zéro échec**, 37,12 secondes.
- Suite Mac Debug du même code fonctionnel, avant changement du numéro de version : **304 tests, zéro échec**, 41,78 secondes.
- Extension navigateur : **60 tests, zéro échec**. Premier lancement impossible faute de `jsdom` dans le dépôt ; installation des dépendances verrouillées dans la copie de construction sur le SSD interne, puis suite complète réussie.
- Parité des sept fichiers d’annotation partagés avec EasyShoot : conforme.
- Trois cycles réels de recherche, aperçu, fermeture et réouverture ont confirmé le focus du champ de recherche sans clic préalable.

Les tests du compteur couvrent la persistance chiffrée, le réglage actif par défaut, le décompte par élément, les limites numériques et le nettoyage après suppression. Les tests de focus couvrent l’attachement, les réouvertures, l’isolation entre fenêtres et la synchronisation du texte. Les tests de défilement couvrent les tuiles et leurs espaces dans les quatre configurations normal/compact avec aperçu ouvert/fermé.

## Limites

Le test natif de défilement passait aussi avant la correction. L’outil de contrôle ne reproduit pas fidèlement le geste horizontal du trackpad : la disparition du blocage signalé entre les tuiles reste à confirmer avec le périphérique de l’utilisateur. Le changement étend les zones de réception aux espaces et aux marges, sans nouveau gestionnaire de défilement.

Le compteur mesure les commandes de collage envoyées par EasyPaste, sans confirmation de l’application cible. Les collages manuels externes ne sont pas observés. Les parcours réels Bitwarden, webcam/micro, YouTube, l’exécution sur Intel et une installation OTA complète depuis une ancienne version ne sont pas déclarés rejoués pour cette livraison.

La distribution conserve l’identifiant `app.easypaste.mac`, le certificat Developer ID « Les papas du code » et la clé publique Sparkle existants. La compilation universelle, la signature, la notarisation et la vérification des fichiers téléchargés sont obligatoires avant l’avancement du flux. Les résultats de publication sont consignés dans le document de reprise du dépôt.
