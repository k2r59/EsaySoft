# Validation EasyPaste 0.3.10

2 novembre 2026. Publication autorisée par Hervé après confirmation du fonctionnement de Maj + molette dans la version privée. Version 0.3.10, build 27.

## Code livré

- 335 tests Release sans échec, 44,557 s, sur les sources fonctionnelles avant changement du numéro de version ; log local `/tmp/easypaste-shift-scroll-full.log`.
- Quatre tests de défilement : événements pixels et lignes, deux sens, cartes et interstices, modes compact/normal, aperçu ouvert/fermé, Maj vertical ou déjà horizontal. Exclusion des événements précis du trackpad, des autres modificateurs et des zones hors de la rangée. Validation manuelle finale par Hervé sur le paquet privé.
- Treize tests des raccourcis : valeurs par défaut, persistance, réinitialisation, conflits, restauration des enregistrements natifs et clavier alternatif. Essais UI de saisie, conflit, annulation, réinitialisation et ouverture réelle d'un aperçu avec une combinaison personnalisée.
- Sept tests spécifiques FileZilla/Sheets, ainsi que les tests existants de presse-papiers texte enrichi/valeurs. Essais réels dans le Gestionnaire de sites de FileZilla, dans deux feuilles Sheets ouvertes dans Arc et dans TextEdit ; détails et limites dans `QA-PASTE-COMPATIBILITY-2026-11-02.md`.

## Limites

La connexion rapide de FileZilla n'est pas déclarée corrigée : échec reproduit aussi avec la version installée d'origine. Le raccourci manuel propre à FileZilla et le menu interne Collage spécial de Sheets ne sont pas remplacés par les adaptations d'EasyPaste. Aucun transfert FTP effectué. Le problème de copie dans l'aperçu XLSX de Claude n'est pas déclaré corrigé.

Pas de nouveau parcours caméra/micro/Bitwarden pour cette livraison, ni d'exécution sur un Mac Intel. Le contrôle du flux public et des archives ne vaut pas essai d'installation OTA complète depuis une ancienne version.

La publication conserve l'identifiant, le certificat Developer ID et la clé Sparkle. Compilation universelle, notarisation Apple, signatures du paquet et du flux et empreintes des fichiers téléchargés requises avant annonce de disponibilité. Résultats consignés dans le document de reprise.
