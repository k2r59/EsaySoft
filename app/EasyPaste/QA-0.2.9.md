# EasyPaste 0.2.9 — partage Bitwarden

## Parcours

Bitwarden est désactivé par défaut. Son activation dans Réglages → Intégrations
affiche un menu dédié dans la barre de menus et sur les cartes. La connexion est
native, sans CLI. Aucun historique n’est synchronisé avec Bitwarden.

Avec **Lien public uniquement**, l’action **Copier un lien** crée un partage de
7 jours, nommé avec la date et l’heure, puis copie le lien. Une petite fenêtre
non activante indique l’avancement et permet d’annuler. **Partager avec options…**
ouvre ponctuellement le formulaire : titre, durée, mot de passe facultatif ou
adresses e-mail autorisées. **Mes partages** permet de recopier ou supprimer un lien.

Les images conservent leurs octets d’origine. Les fichiers, vidéos et textes longs
nécessitent les droits d’envoi de fichiers de Bitwarden ; l’accès par e-mail dépend
également d’un abonnement compatible. Voir [le guide](docs/bitwarden.md).

## Vérifications du 19 octobre 2026

La suite compte 181 tests, dont 35 pour Bitwarden. Les tests réseau utilisent un
transport simulé ou URLProtocol ; aucun compte ni contenu personnel n’est envoyé.
La dernière passe Release a réussi sans échec en 23,25 secondes, après une passe
intermédiaire de 177 tests et plusieurs exécutions ciblées. Les binaires produits
contiennent arm64 et x86_64 ; leurs commandes de chargement déclarent macOS 15.0
comme version minimale. Le générateur d’icône écrit désormais des dimensions en
pixels explicites pour fonctionner aussi sur un écran Retina.

- Vecteurs PBKDF2 et Argon2id de Bitwarden, HKDF RFC 5869 et dérivation Send.
- Chiffrement authentifié, altérations de MAC et 500 variantes tronquées ; refus
  des paramètres KDF excessifs, réponses trop grandes et hôtes d’envoi non autorisés.
- Chiffrement d’un fichier par blocs, restitution exacte, annulation et refus des
  liens symboliques. Les fichiers temporaires sont conservés pendant leur utilisation
  par un worker, puis supprimés après réussite, fermeture ou annulation.
- Connexion, renouvellement, vérification d’un nouvel appareil, authentification
  en deux étapes, CAPTCHA non pris en charge, réponses invalides et erreurs Premium.
- Module désactivé sans appel réseau ni lecture de session ; activation explicite,
  désactivation pendant un envoi, verrouillage et oubli de la connexion.
- Mode rapide fixé à 7 jours et titre daté ; une seule création et une seule copie
  malgré un double clic. Le formulaire ponctuel conserve le réglage rapide.
- Validation et normalisation des e-mails ; séparation des modes public, mot de
  passe et e-mail dans la requête chiffrée.
- Copie après réussite de l’envoi ; nettoyage distant après échec d’upload ; aucun
  nouvel essai automatique d’une création dont la confirmation est inconnue.
- Refus d’authentification locale et annulation empêchant la lecture de session.
- Rendus SwiftUI hors écran de la connexion, du formulaire et de l’envoi rapide.
  Les captures utilisent des données fictives et ont été inspectées visuellement.
- Régression de l’historique, de l’annotation, des captures, de la vidéo, des formats
  structurés, de Markdown, du SVG et de la pipette.

Une sonde séparée signée avec Developer ID a vérifié le véritable trousseau macOS
avec des valeurs fictives : création, lecture, mise à jour, restauration par une
nouvelle instance, suppression et absence du jeton d’accès dans la valeur persistée.
L’essai a confirmé que le trousseau Data Protection retourne `-34018` sans profil
de provisioning. La version distribuée utilise le trousseau de connexion avec
son ACL par défaut et une validation LocalAuthentication avant restauration.
La sonde n’a lu aucun identifiant existant et a supprimé son propre élément.

## Ressources

Les dérivations de clé sont sérialisées hors du thread principal. PBKDF2 est borné
à deux millions d’itérations ; Argon2id à 256 Mio, dix passes et seize lanes.
Le chiffrement de fichier traite des blocs de 1 Mio, puis URLSession envoie le
fichier chiffré depuis le disque. Les retours d’avancement sont limités au changement
du pourcentage entier. Aucun polling réseau n’est effectué à l’inactivité.

## Limites de la validation

Les tests simulés ne démontrent pas l’interopérabilité de bout en bout avec un
compte réel. La connexion à Bitwarden EU/US, l’ouverture du lien par un destinataire,
le code d’accès envoyé par e-mail et le téléchargement réel d’un fichier restent
à valider avec un compte volontaire. La fenêtre système Touch ID / authentification
du Mac n’a pas été validée manuellement. L’exécution sur un Mac Intel reste à tester.

L’intégration utilise le protocole des clients Bitwarden, dont les interfaces
internes peuvent évoluer. Elle demeure facultative et désactivée par défaut.
La signature et la notarisation Apple ne remplacent pas ces essais fonctionnels.

## Reproduire

```sh
EASYPASTE_LAYOUT_SNAPSHOTS="$PWD/.build/bitwarden-snapshots" swift test -j 2 -c release
```

Le code original reste sous licence MIT ; le composant Argon2 conserve la licence
CC0 choisie parmi ses licences d’origine. Voir [les mentions tierces](THIRD-PARTY-NOTICES.md).
