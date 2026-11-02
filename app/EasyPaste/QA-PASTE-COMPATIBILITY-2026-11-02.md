# Compatibilité du collage — tests locaux du 2 novembre 2026

## Périmètre autorisé

Adapter seulement le collage depuis EasyPaste vers le Gestionnaire de sites de
FileZilla et le collage sans mise en forme dans Google Sheets. L'utilisateur
demande de préserver les comportements existants. Aucune publication autorisée
pour cette évolution ; ne pas avancer le flux Sparkle ni le numéro de version.

## Implémentation

- `PasteCompatibility.swift` : exceptions explicitement limitées aux destinations.
- FileZilla : identifiant `org.filezilla-project.filezilla`, fenêtre de sous-rôle
  `AXDialog` et titre exact « Gestionnaire de sites » ou « Site Manager ».
  Les autres fenêtres gardent la simulation de ⌘V. Une identification absente
  ne suffit pas à activer une exception.
- Dans cette fenêtre, seuls les champs texte activés sont adaptés. L'insertion
  utilise la sélection accessible si elle est modifiable, sinon la valeur et la
  plage UTF-16 vérifiées. Le début et la fin du champ sont conservés. Les plages
  invalides, les coupures de paires UTF-16 et les caractères de contrôle sont refusés.
- Le champ sécurisé utilise, si nécessaire, des événements texte Unicode courts,
  sans Commande ni Retour. Le mot de passe existant n'est pas lu ni réécrit.
  Limite : 1 024 unités UTF-16. Aucun nouvel essai automatique après un échec
  pouvant avoir inséré une partie du contenu.
- Le champ du nom du site disparaît à la désactivation de FileZilla. EasyPaste
  mémorise uniquement le contexte de cet éditeur directement rattaché à la fenêtre,
  réouvre « Renommer » si nécessaire, vérifie la fenêtre et le nom, puis restaure
  la sélection avant l'insertion. Il ne mémorise pas les valeurs des autres champs.
- Sheets : uniquement l'action explicite sans mise en forme, un navigateur reconnu
  et une URL HTTPS `docs.google.com/spreadsheets/d/<identifiant>`. Envoie ⇧⌘V
  avec le texte brut déjà produit par `History.copy`. La détection de page utilise
  l'Accessibilité existante, bornée et exécutée hors du thread principal.
- Aucune modification du collecteur, du coffre, des représentations HTML/RTF,
  de l'extension Chrome, du collage normal ni des autres applications.
- Les contrôles de destination restent présents avant et après les opérations
  asynchrones. Une insertion refusée ne consomme pas la pile ni le compteur.

## Automatisation

Dernière exécution sur les sources finales : **319 tests Release, zéro échec**, en
40,41 s. Journal local : `/tmp/easypaste-compatibility-full.log`.

Sept tests ajoutés : périmètre FileZilla, périmètre Sheets, refus des URL voisines,
insertion avec préfixe/suffixe, Unicode, plages invalides/limites/caractères de
contrôle, reconstruction des événements sécurisés sans modificateurs ni perte de
texte. Les tests existants de destination, de presse-papiers HTML/texte brut et de
stockage chiffré passent.

Les premiers tests ont trouvé deux défauts du nouveau calcul de sélection
(plage hors limites et frontière au milieu d'une paire UTF-16), corrigés avant
validation. Ils ne doivent pas être confondus avec un crash de l'application
installée.

La suite complète a aussi révélé une course dans
`ImageVariantTests.testImageSaveAlwaysPreservesOriginalAndEarlierVariants` :
l'OCR automatique pouvait terminer après la préparation du texte OCR fictif.
Le test attend maintenant, avec limite de cinq secondes, la fin de l'OCR initial.
Le traitement des images en production n'a pas été modifié. Deux suites complètes
successives après cette stabilisation sont passées ; la seconde inclut le dernier
ajustement de périmètre et le message « Valeurs collées dans Google Sheets ».

## Essais réels

FileZilla local **3.71.1**, interface française, site temporaire non enregistré,
texte fictif `easypaste-test.invalid`. Aucune connexion FTP effectuée.

| Cas | Résultat |
| --- | --- |
| Gestionnaire de sites, Hôte vide | Texte inséré, aucune validation du formulaire |
| Gestionnaire de sites, Utilisateur vide | Texte inséré, aucune validation |
| Gestionnaire de sites, Mot de passe vide | 22 caractères masqués insérés |
| Mot de passe, remplacement des 5 derniers caractères | 39 caractères masqués, longueur attendue |
| Nom du site, remplacement total | Nouveau nom inséré malgré la fermeture de l'éditeur à la désactivation |
| Nom du site, remplacement du seul mot « test » | Préfixe et suffixe conservés |
| Hôte, remplacement du seul mot « test » | Préfixe et suffixe conservés |
| Connexion rapide, collage EasyPaste | Non validé : échec également reproduit avec la version installée d'origine |
| Connexion rapide, raccourci ciblé par l'outil | Le texte apparaît ; comportement différent de l'envoi EasyPaste |
| TextEdit, document vierge « Sans titre 3 » | Collage normal de la tuile réussi |

Le site temporaire a été annulé, pas enregistré. Ne pas annoncer que le raccourci
manuel de FileZilla ou que tous ses champs sont réparés. L'exception vise le
Gestionnaire de sites et le collage déclenché par EasyPaste. Le résultat antérieur
de connexion rapide rapporté comme réussi n'est pas reproductible dans l'état
final de cette session. Une comparaison A/B a confirmé le même échec avec le
binaire original `/Applications/EasyPaste.app` : ce point reste à investiguer.

Google Sheets, dans Arc, documents fictifs créés lors de l'investigation :

- B : `https://docs.google.com/spreadsheets/d/1VFr7J3YRujun5VZ9OgaIJrvINNwAl4sxCzJYctnOcmo/edit`.
- Copie locale de `A1:B1` (EP-B-777 et résultat 777), puis rappel de l'ancienne
  tuile du classeur A (EP-A-42 et résultat 42).
- Collage sans mise en forme depuis EasyPaste, via ⇧Retour, vers `D11:E11` :
  **EP-A-42 et 42**. Sélection de `E11` : barre de formule **42**, sans formule.
- Collage normal vers `D13:E13` : **EP-A-42**, deux cellules sélectionnées après
  collage. Les tests d'intégration vérifient également l'intégrité HTML/texte brut.
- Le menu interne « Collage spécial » de Sheets n'est pas modifié. Pour ce flux,
  utiliser « Coller sans mise en forme » dans EasyPaste (⇧Retour).
- Pas de test avec l'application concurrente Paste, absente de ce Mac.

## Paquet et installation

Paquet privé arm64, construit sur SSD interne, signé avec le Developer ID existant
et vérifié strictement :
`/Users/k2r59/Library/Caches/EasyPaste-local-install/compatibility-20261102/EasyPaste.app`.

SHA-256 du binaire privé final :
`5ba0394acb1df06f9c212aecc4bb236934e7c5a12c5e7f6ee3370f47565fc31e`.

La tentative de remplacement dans `/Applications` a été refusée par macOS
(`Operation not permitted`). Aucun contournement de permission n'a été effectué.
La signature et l'empreinte de la version installée sont restées valides et
inchangées :
`1c198199703c7d5f1d37bb560dbeed458bf453cadad86a936f3166c7eba76ad1`.
Les essais ont utilisé le paquet privé depuis le cache, puis la version installée
pour la comparaison A/B. Sauvegarde : `before-compatibility.zip` dans le même dossier.

Le paquet privé reprend le numéro **0.3.9 (26)** mais n'est ni la release publique
ni un installateur de distribution. Pas de DMG, notarisation, tag, commit, push ou
changement OTA pour cette évolution. Les sources et ce rapport restent dans la
branche de travail `codex/reprise-easypaste-2026-10-24`.
