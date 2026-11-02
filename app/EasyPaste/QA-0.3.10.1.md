# Validation EasyPaste 0.3.10.1

2 novembre 2026. Publication autorisée par Hervé après confirmation du fonctionnement de la version privée 0.3.11-beta.1 avec sa souris Logitech. Version publique demandée : 0.3.10.1. Build 29, supérieur à la version publique 27 et à la bêta locale 28.

## Périmètre et preuves

- Nouveau routage des événements de défilement dans ShelfPanel.sendEvent, sur toute la surface visible de la rangée ; suppression du moniteur local et du filtre excluant les événements précis.
- Maj + molette vertical converti en horizontal seulement si nécessaire, conservation des trois représentations de delta et des phases ; événements déjà horizontaux inchangés.
- Références faibles, retrait au détachement, clics inchangés, aucun ajout de minuterie ou chargement anticipé des cartes.
- **338 tests Release sans échec**, 53,596 s, sur le code livré avant changement du numéro de version ; journal local /tmp/easypaste-window-scroll-full.log.
- Sept tests de défilement, dont passage par panel.sendEvent : événements ligne/pixel, axes vertical/horizontal, Maj, deux sens, interstices à différentes hauteurs, normal/compact, aperçu ouvert/fermé, phases et inertie, retrait du pont.
- Validation manuelle par Hervé : « la version beta fonctionne en local », après le test demandé Maj + molette entre les tuiles.

## Limites

Les tests synthétiques ne couvrent pas physiquement tous les modèles de souris. Pas de nouvelle exécution de l’app sur Mac Intel ni de nouveau parcours caméra/micro/Bitwarden. Les fonctions hors défilement ne changent pas. Le contrôle du flux et des archives ne constitue pas à lui seul une installation OTA complète.

Construction universelle, signature Developer ID, notarisation Apple, signatures Sparkle et téléchargement des archives à vérifier avant annonce de disponibilité. Résultats définitifs dans le document de reprise.
