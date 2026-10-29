# Validation EasyPaste 0.3.9

29 octobre 2026. Publication autorisée par Hervé. Version 0.3.9, build 26.

## Vérifications du code livré

- 312 tests Release sans échec, en 37,84 s, exécutés sur les sources fonctionnelles livrées avant changement du numéro de version.
- 19 tests d’intégration Bitwarden avec transport simulé : ajout du lien complet dans le coffre chiffré et la pile, modes rapide et formulaire, pile enregistrée ou non, absence de doublons, original intact, erreurs de copie et d’écriture, annulation et échec de transfert.
- Tests d’enregistrement sans remplacement : variantes distinctes pour les formats structurés, texte enrichi et extraits identiques ; conservation des octets de l’original.
- Test de rendu des interrupteurs dans un panneau de production, en clair et en sombre. Six transitions réelles micro, webcam et son système vérifiées lors de la livraison privée précédente.
- Compilation universelle et signature stricte du correctif privé vérifiées avant son installation locale.

## Limites

Aucun Send réel créé sur le compte utilisateur pendant ces tests. Pas de nouvel essai webcam, micro ou YouTube pour cette livraison. Le dernier relancement privé est confirmé par le processus ; CUA a renvoyé une erreur ScreenCaptureKit -3811 empêchant une nouvelle vérification visuelle. Une installation OTA complète depuis une ancienne version et l’exécution sur Mac Intel ne sont pas déclarées testées.

La publication doit vérifier la notarisation Apple, les signatures du paquet et du flux Sparkle, puis les empreintes des fichiers téléchargés depuis la release avant d’avancer le flux public. Les résultats sont consignés dans le document de reprise.
