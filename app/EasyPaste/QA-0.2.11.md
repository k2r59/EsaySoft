# EasyPaste 0.2.11 — serveur Bitwarden unique

Les nouvelles connexions et demandes de code par e-mail utilisent uniquement
`bitwarden.com`. Le sélecteur Europe/International est retiré. Le domaine
est indiqué sous le titre de la fenêtre.

Le choix est appliqué dans le modèle, pas seulement dans la vue. Une préférence
Europe conservée d'une ancienne version ne change pas la destination d'une
nouvelle connexion. Les anciennes sessions conservent néanmoins leur hôte
d'origine : aucun jeton EU n'est envoyé au serveur International.

Le test de connexion existant vérifie la destination International. Un test
supplémentaire couvre une préférence Europe résiduelle et vérifie les hôtes de
toutes les requêtes ainsi que la région enregistrée après connexion.
Les tests de restauration des sessions EU continuent de vérifier la compatibilité.

Le 20 octobre 2026, les **40 tests Bitwarden passent sans échec**, en 2,66 secondes
(`swift test -j 2 -c release --filter Bitwarden`). La vue de connexion native a
été rendue et inspectée : domaine International visible, aucun sélecteur Europe.
La passe complète de 185 tests de la version 0.2.10 avait également réussi.

Avec la version 0.2.10 et le serveur International, le compte utilisateur a atteint
la demande de code d'authentification. L'utilisateur a ensuite confirmé la réussite
de la connexion, également constatée dans l'interface (session déverrouillée).
Cela ne valide pas encore la création et l'ouverture d'un partage complet.
Les limitations de compatibilité documentées dans les versions précédentes
restent applicables.
