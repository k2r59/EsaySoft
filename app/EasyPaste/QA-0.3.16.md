# EasyPaste 0.3.16 — préparation du 24 novembre 2026

## Correctif OCR

Base : tag easypaste-v0.3.15, commit 767f78f. L’extraction enregistre et copie uniquement public.utf8-plain-text. La reconstruction HTML et son API sont supprimées. Les lignes restent triées de haut en bas, leurs fragments de gauche à droite ; les fragments proches sont réunis, les colonnes nettement séparées utilisent ` | `.

Les anciennes entrées enrichies ne sont pas migrées : elles restent accessibles en texte brut via l’action existante. La copie HTML des contenus web est préservée.

## Validation

- Tests de régression en échec avant correction : présence de HTML dans le presse-papiers et séparateurs de colonnes.
- 19 tests ciblés réussis : OCR réel sur image de tableau, observations inversées et en ordre par colonne, conservation des blocs, nettoyage des anciens formats du presse-papiers, stockage chiffré en texte seul et copie web inchangée.
- Suite complète `swift test -j 2 -c release` : 406 tests exécutés, 403 réussis, 3 ignorés, aucun échec. Les tests ignorés nécessitent les moteurs packagés ou le mode réseau optionnel.
- Le test OCR réel des cartes vérifie explicitement le nom en première ligne, l’ID immédiatement dessous, la date et son badge en troisième ligne, puis le statut et Stripe card sur la même quatrième ligne, dans cet ordre.
- Une première image synthétique de tableau a révélé que Vision omettait un chiffre isolé ; le test stable utilise une valeur à deux chiffres. Ce correctif ordonne les fragments reconnus, il ne garantit pas la reconnaissance de tous les caractères ni la restitution des cellules vides ou fusionnées.
- Compilation universelle arm64/x86_64, cible minimale macOS 15.0, SDK 27.2 ; signature locale ad hoc vérifiée.
- Les ressources et moteurs inchangés du paquet local préparatoire proviennent de l’application 0.3.15 installée, dont la signature profonde a été vérifiée avant copie. Vérification des 107 composants natifs universels et des quatre moteurs réussie.

## État de livraison

Version 0.3.16, build 45 préparés. Le paquet local n’est pas un paquet de distribution : signature ad hoc uniquement. Aucun remplacement de /Applications/EasyPaste.app, aucune notarisation, aucune release ni modification du flux public à ce stade.

Configuration encore nécessaire sur le Mac de préparation : identité Developer ID Application de l’équipe WN9MHL56A9, profil de notarisation EasyShoot et clé Sparkle du compte app.easypaste.mac. L’utilisateur a accès à l’ancien Mac et demande une assistance pour transférer cette configuration. Les secrets ne doivent pas être ajoutés au dépôt.
