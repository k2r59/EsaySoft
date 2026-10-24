# Vérification locale — 0.2.0

Date : 24 octobre 2026. Aucun envoi au Chrome Web Store, aucune publication GitHub.

## Tests automatiques

55 tests passent avec Node 25.6.1 et jsdom 26.1.0. La suite 0.2.0 a passé 55 tests, dont les 47 régressions de la version précédente. Durée finale : environ 2 secondes. Une fixture de 220 paragraphes avec emphases et liens s’extrait en environ 65 ms dans jsdom, en cédant six fois la main à la boucle d’événements. Ce chiffre ne mesure pas les performances d’une page réelle dans Chrome.

Vérifications :

- Sélection partielle de texte, balisage riche, listes, tableaux, liens relatifs, source facultative, contraste de texte blanc sur fond sombre.
- Scripts, gestionnaires d’événements, SVG, MathML, frames, objets, images distantes, formulaires, éléments cachés et CSS actif retirés.
- URL dangereuses, fausse balise base, injection d’attribut, dépassement de profondeur ou de volume refusés.
- Transcriptions JSON3 et XML, langues, sous-titres automatiques, XML/JSON malformé, entités, réponse vide, HTML d’erreur, budgets et chronométrage.
- Navigation YouTube interne : refus de réutiliser les pistes de la vidéo précédente. URL de piste limitée à la vidéo et l’origine actuelles, redirections interdites.
- Réseau indisponible, HTTP 403, réponse trop grosse : message explicite, aucune fausse réussite.
- Panneaux natifs YouTube anciens et modernes, avec ou sans `target-id`, texte attribué et horodatage séparés.
- Ouverture explicite du panneau, attente de son rendu, arrêt si la vidéo change, refus d’une transcription filtrée par recherche.
- Liste virtualisée : récupération de chaque ligne et restauration du défilement initial.
- Piste directe vide : repli natif avec une seule piste ; aucune substitution de langue silencieuse avec plusieurs pistes.
- Popup : MIME HTML et texte brut ensemble, page non autorisée, navigation pendant l’ouverture, presse-papiers refusé.
- Permissions : les trois permissions de copie restent inchangées ; `nativeMessaging` est facultative. Aucun hôte web permanent, worker ou collecte de fond.
- Identité publique stable, nonce aléatoire de 48 caractères, contrat natif strict, refus des champs inattendus et des réponses incohérentes.
- Vérification native ponctuelle : délai maximal, hôte absent/non autorisé, permission refusée, retrait limité à nativeMessaging, contenu des erreurs rendu comme texte.
- Aucune vérification native automatique à l’ouverture ; demande de permission dans le clic direct ; contrôles de copie indépendants de la connexion.
- Métadonnée source : URL réelle de la page malgré faux `canonical` ou `meta`, attribution visible désactivée, sélection exacte, absence de modification du texte brut.
- Source : HTTP(S) uniquement, rejet des identifiants, caractères de contrôle, URL relatives ou trop longues. Entités HTML et Unicode préservés par sérialisation DOM.
- Transcription : HTML `<pre>` sûr, balisage cité rendu comme texte, source dans `<head>`, limite de 2 Mo appliquée après ajout des métadonnées.

## Validation de la connexion 0.2.0

Les échanges natifs sont couverts par mocks de l’API Chrome ; la vérification native réelle, l’installation de l’hôte et l’essai Arc restent à effectuer avec l’app correspondante. Aucun résultat de ces tests simulés n’est présenté comme un handshake réel. L’extension 0.2.0 n’a pas été chargée dans le navigateur par cette tâche.

Le scanner natif de métadonnées a aussi été remplacé dans `BrowserOrigin.swift` : lecture bornée à 64 Ko, respect des attributs entre guillemets, exclusion des commentaires et éléments raw/inertes, URL jusqu’à 8192 octets après normalisation. Trois tests Swift supplémentaires couvrent l’expansion des entités, les balises citées et les entrées malformées. Ils sont préparés pour l’exécution native coordonnée ; ils n’ont pas été exécutés par l’agent de l’extension.

## Vérification réelle du navigateur

Dans Chrome, le moteur a été exécuté sur `tests/browser-fixture.html`, hors extension : copie système HTML + texte puis collage avec ⌘V dans un champ riche. Le destinataire a reçu les deux types MIME et confirmé le gras, le tableau et l’absence de texte masqué/SVG. Couleurs, italique, listes et liens ont été vérifiés visuellement. Extraction mesurée à 0,9 ms sur cette petite fixture. Le popup YouTube a été rendu en mode sombre et inspecté à sa largeur de 390 px : texte lisible, contrôle principal visible, section de page repliée. Son contenu de démonstration est explicitement signalé.

### Régression YouTube et correction réelle (0.1.1)

L’utilisateur a ensuite installé la 0.1.0. L’erreur « piste vide » a été reproduite dans son Chrome sur la vidéo `T0aGmpVzFKg`, alors que le bouton natif **Afficher la transcription** donnait accès à 377 passages. L’ancienne lecture DOM ne reconnaissait pas la structure moderne du panneau. L’origine exacte de la réponse réseau vide n’est pas affirmée ; aucun changement de jeton, client, signature ou restriction d’accès n’a été tenté.

L’extension existante a été mise à jour en **0.1.1**, dans `/Users/k2r59/Desktop/EasyPaste-Web`, puis rechargée depuis sa fiche Chrome. Version 0.1.1 affichée. Permissions inchangées, aucune nouvelle extension ni autorisation ajoutée.

Deux essais ont réussi via le vrai popup de l’extension :

1. Panneau transcription fermé : **Copier les sous-titres** a ouvert automatiquement le panneau natif et annoncé **377 passages**. Un collage ⌘V dans une fixture locale a reçu **33 266 caractères, 377 lignes**, sans horodatage.
2. Option **Inclure les repères de temps** activée : nouvelle copie réussie, collage local de **36 282 caractères, 377 lignes toutes horodatées**.

Le texte n’a été envoyé à aucun service externe. La fixture affiche uniquement des mesures ; elle ne conserve pas la transcription. Son onglet a été fermé et son serveur 127.0.0.1 arrêté. La vidéo utilisateur a été laissée ouverte, en pause. Le presse-papiers contient la deuxième copie demandée ; aucune donnée de l’historique utilisateur n’a été supprimée.

Cette validation porte sur une vidéo réelle publique dans le Chrome de l’utilisateur. Les variantes ancien panneau, liste virtualisée, HTTP vide, refus, recherche active et navigation pendant l’attente sont couvertes par fixtures ; elles ne sont pas présentées comme autant de vidéos réelles testées.

### Origine des copies — vérification réelle 0.1.2

L’extension installée a été mise à jour et rechargée en 0.1.2 dans le même dossier, sans nouvelle permission. Tests via le vrai popup Chrome :

1. Une page de fixture locale a été copiée avec **Ajouter le lien de la source décoché**. Le collage dans une autre fixture a reçu `text/plain` et `text/html`, 224 caractères et la métadonnée exacte `http://127.0.0.1:8767/tests/browser-fixture.html?source=a&second=b`. Le `&` de l’adresse a traversé la sérialisation et le presse-papiers correctement. Le texte n’avait pas de source visible ajoutée.
2. La transcription de la vidéo `T0aGmpVzFKg` a été recopiée : 377 lignes, 33 266 caractères, exactement le même volume de texte brut que la 0.1.1. Le collage a reçu les deux formats et la source `https://www.youtube.com/watch?v=T0aGmpVzFKg` dans la métadonnée HTML.

La fixture lit les types MIME au collage et la balise source via DOMParser. Elle n’exécute pas le contenu, ne l’affiche pas et ne l’envoie nulle part. Son onglet a été fermé via son bouton Fermer ; le serveur local a été arrêté. Aucun réglage ou permission Chrome n’a changé. Le document TextEdit de l’utilisateur est resté intact. La validation du bouton d’origine dans l’app macOS est menée séparément ; ce contrôle porte sur les données réellement transmises par l’extension.

## Limites connues

L’accès aux pistes YouTube dépend de son lecteur actuel et peut être refusé même lorsqu’une vidéo propose des sous-titres à l’écran. Le recours au panneau de transcription est proposé sans contourner ce refus. Les images distantes et les contenus intégrés ne sont pas incorporés. Le HTML nettoyé conserve la mise en forme textuelle, pas une reproduction pixel pour pixel de la page.
