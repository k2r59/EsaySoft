# EasyPaste 0.2.10 — connexion Bitwarden

## Défaut corrigé

La version 0.2.9 omettait les en-têtes `Bitwarden-Client-Name` et
`Bitwarden-Client-Version`. Le validateur du serveur Bitwarden exige une version
après validation des identifiants et retourne `version_header_missing` si elle
manque. EasyPaste transformait tous les refus HTTP 400/401 en erreur
d'identifiants, masquant notamment ce refus.

La version 0.2.10 envoie ces en-têtes pour la connexion, le renouvellement et les
requêtes API. Elle annonce sa propre version, sans revendiquer le support du
chiffrement V2. Un refus `invalid_client_version` reste bloquant et indique une
incompatibilité. Aucun mécanisme de sécurité Bitwarden n'est contourné.

## Vérifications

La suite Release du 20 octobre 2026 passe : **185 tests, aucun échec**, en
23,23 secondes (`swift test -j 2 -c release`). Les tests Bitwarden utilisent
un transport simulé ; ils ne manipulent aucun identifiant utilisateur.

Quatre tests supplémentaires couvrent les en-têtes sur les deux régions et le
renouvellement, la distinction des erreurs de client et d'identifiants, les
réponses non JSON et HTTP 429, ainsi que le refus d'un code de vérification.
Les tests vérifient aussi qu'un message serveur arbitraire n'est pas affiché,
qu'aucune tentative n'est répétée automatiquement et que les identifiants ne
sont jamais envoyés à l'autre région.

Une requête ponctuelle avec un compte fictif du domaine réservé `example.invalid`
a confirmé l'accessibilité du serveur EU et son format de refus d'identifiants.
Cette sonde ne valide pas une connexion à un compte réel.

## Limites

Le défaut d'en-tête est confirmé par comparaison avec le validateur officiel.
Sans réponse du compte réel après mise à jour, il n'est pas possible d'affirmer
qu'il était l'unique cause du refus observé. L'authentification complète,
la création et l'ouverture d'un Send restent à confirmer avec le compte utilisateur.
Les limites de compatibilité de 0.2.9 restent applicables.

Sources consultées le 20 octobre 2026 :

- https://github.com/bitwarden/server/blob/main/src/Identity/IdentityServer/RequestValidators/ClientVersionValidator.cs
- https://github.com/bitwarden/server/blob/main/src/Identity/IdentityServer/RequestValidators/BaseRequestValidator.cs
- https://github.com/bitwarden/clients/blob/main/libs/common/src/services/api.service.ts
