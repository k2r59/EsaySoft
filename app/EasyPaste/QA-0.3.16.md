# EasyPaste 0.3.16 — validation du 26 novembre 2026

## Correctif OCR

Base : tag easypaste-v0.3.15, commit 767f78f. L’extraction enregistre et copie uniquement public.utf8-plain-text. La reconstruction HTML et son API sont supprimées. Les lignes restent triées de haut en bas, leurs fragments de gauche à droite ; les fragments proches sont réunis, les colonnes nettement séparées utilisent ` | `.

Les anciennes entrées enrichies ne sont pas migrées : elles restent accessibles en texte brut via l’action existante. La copie HTML des contenus web est préservée.

## Validation

- Tests de régression en échec avant correction : présence de HTML dans le presse-papiers et séparateurs de colonnes.
- 19 tests ciblés réussis : OCR réel sur image de tableau, observations inversées et en ordre par colonne, conservation des blocs, nettoyage des anciens formats du presse-papiers, stockage chiffré en texte seul et copie web inchangée.
- Suite complète `swift test -j 2 -c release` : 406 tests exécutés, 403 réussis, 3 ignorés, aucun échec. Les tests ignorés nécessitent les moteurs packagés ou le mode réseau optionnel.
- Le test OCR réel des cartes vérifie explicitement le nom en première ligne, l’ID immédiatement dessous, la date et son badge en troisième ligne, puis le statut et Stripe card sur la même quatrième ligne, dans cet ordre.
- Une première image synthétique de tableau a révélé que Vision omettait un chiffre isolé ; le test stable utilise une valeur à deux chiffres. Ce correctif ordonne les fragments reconnus, il ne garantit pas la reconnaissance de tous les caractères ni la restitution des cellules vides ou fusionnées.
- Compilation universelle arm64/x86_64, cible minimale macOS 15.0, SDK 27.2 ; signature Developer ID de l’équipe WN9MHL56A9 vérifiée.
- Les ressources et moteurs inchangés du paquet local préparatoire proviennent de l’application 0.3.15 installée, dont la signature profonde a été vérifiée avant copie. Vérification des 107 composants natifs universels et des quatre moteurs réussie.

## État de livraison

Version 0.3.16, build 45 signés avec Developer ID Application et acceptés par Apple le 26 novembre 2026 (soumission abb72b85-d9e4-46a0-99f3-ea22b767f2e8). Tickets attachés à l’application et au DMG ; validations stapler et Gatekeeper réussies.

Installation locale dans /Applications/EasyPaste.app, redémarrage et affichage de « Version 0.3.16 » vérifiés. L’historique existant reste visible et la collecte reste en pause comme avant l’installation. L’ancienne application est conservée hors du dépôt pour permettre un retour arrière.

Le paquet réutilise les moteurs inchangés et vérifiés de 0.3.15. Les sept archives et licences tierces sont reprises de l’archive source publiée de 0.3.15, après vérification de son SHA-256. Le code OCR et l’exécutable principal correspondent au correctif testé de cette version.

La publication utilise le profil de notarisation EasyPaste et la clé Sparkle du compte app.easypaste.mac, dans le trousseau local. Aucun secret ne figure dans les sources ni les archives. Le script de publication vérifie le flux et le DMG signés, puis contrôle les archives retéléchargées avant d’annoncer la mise à jour.

Limite de validation : installation locale directe effectuée ; une mise à jour Sparkle complète depuis 0.3.15 n’a pas été exécutée sur ce Mac.
