# Récupération de la playlist Rap 90 2k FR

Contrôle du 29 octobre 2026 sur la [playlist publique fournie](https://open.spotify.com/playlist/2Jp2pyC1epBBstxsmh7NuH).

**Résultat : quatre des cinq titres manquants ont été téléchargés intégralement et validés, avec leur pochette JPEG. Le cinquième reste ambigu et a été refusé.** L’import réel expose 61 titres. La bibliothèque utilisateur en possède toujours 56 ; les quatre fichiers d’essai restent dans `.tools/playlist-061`, sans ajout à cette bibliothèque. Le résultat correspond donc à 60 titres récupérables sur 61 dans le périmètre vérifié, et non à une modification de la bibliothèque de l’utilisateur.

## Résultats par titre

Les durées du fichier viennent de FFprobe. AVFoundation confirme pour chacun des quatre fichiers la lecture possible, une piste audio, aucune piste vidéo de lecture et une pochette JPEG dans les métadonnées. FFprobe classe cette image attachée comme une piste `mjpeg` avec `attached_pic=1` : ce n’est pas une vidéo animée.

| Titre et artiste principal | Durée Spotify | Durée du fichier | Taille exacte | Résultat et source retenue |
| --- | ---: | ---: | ---: | --- |
| Medley Thugs / Interlude, Les Sages Poètes de la rue avec Kool Shen et Nysay | 336,066 s | 336,066 s | 16 334 205 octets | Récupéré ; [YouTube](https://www.youtube.com/watch?v=hyJ5bDFYmIY) ; crédits complets confirmés |
| 16'30 Contre la censure, Eben et le collectif crédité | 1 012,866 s | 1 012,866 s | 48 279 161 octets | Récupéré ; [YouTube](https://www.youtube.com/watch?v=94DFNXy9QEY) ; crédits complets confirmés |
| Beat de Boul est dans la sono, Mala avec Les Sages Poètes de la rue et Sir Doum’s | 224,496 s | 224,496 s | 9 128 803 octets | Récupéré ; [YouTube](https://www.youtube.com/watch?v=M7pfw-SoR14) |
| C’est donc ça nos vies, IAM avec White & Spirit | 312,440 s | 312,215 s | 14 967 084 octets | Récupéré ; [YouTube](https://www.youtube.com/watch?v=KqRvEuwai7I) ; écart de 0,225 s |
| J’avance pour ma familia, Stomy Bugsy avec ses invités, version Medley | 324,093 s | Aucun fichier retenu | Sans objet | Refus cohérent : version non confirmée par les sources examinées |

Chaque fichier accepté contient un flux AAC et une image JPEG attachée, sans vidéo animée. Les empreintes SHA-256, chemins, métadonnées et contrôles détaillés sont consignés dans `.tools/playlist-061/final-verification.json`. Les fichiers de cette passe sont dans `.tools/playlist-061/run-4204A984-08E6-4B32-8A51-09814AC3A656/`.

## Causes et correctifs

Les cinq titres absents possèdent plusieurs artistes crédités. Le rapprochement précédent comparait parfois toute la liste Spotify à un seul crédit YouTube. Les résultats de recherche abrégés peuvent aussi attribuer un morceau collectif à son canal de publication. Ces deux situations écartaient des enregistrements correspondants.

L’import conserve désormais les crédits séparés. Le séparateur réel de la page Spotify est une virgule suivie d’une espace insécable ; une virgule ordinaire dans « Tyler, The Creator » et l’esperluette de « White & Spirit » restent dans le nom. Le rapprochement exige le nom entier de l’artiste principal. Les invités connus dans les titres et dans les métadonnées sont confrontés ; un invité contradictoire ou une inversion artiste principal/invité provoque un refus. L’ordre des invités peut varier. Deux variantes orthographiques secondaires constatées dans ces sources officielles sont normalisées : Les Sages Poètes de la rue / Sages Poètes de la rue et The Insomniak / Insomniak. Les apostrophes des crédits secondaires sont harmonisées, notamment Sir Doum’s / Sir Doums.

Les segments `feat.`, `ft.` ou `featuring` sont traités comme des crédits lorsqu’ils en ont la syntaxe. Un suffixe de version après un séparateur est conservé. Le titre « Featuring You » reste un titre ordinaire. Les garde-fous incluent les homonymes, remix, live, instrumental, Medley, Extended/Radio et éditions 7/12 pouces. Le seuil reste à 0,85. `sameRecording`, utilisé pour réutiliser les fichiers locaux, n’a pas été modifié.

Un candidat déjà suffisamment fiable est essayé immédiatement. Si ces candidats échouent, le moteur peut enrichir au maximum deux résultats plausibles rejetés par service, avec une limite de 10 secondes par inspection. Il réutilise l’exécuteur annulable du streaming. Il vérifie ensuite le même seuil et la durée ; il ne force pas l’acceptation. Les extraits de 30 secondes et les sources protégées rencontrés sur SoundCloud restent exclus.

Les transferts réels ont révélé un autre défaut : la conversion de la vignette WebP pouvait échouer après création de l’audio complet. Le FFmpeg embarqué ne proposait initialement ni l’encodeur PNG actif ni le filtre `mjpeg2jpeg` requis par le [convertisseur de vignettes de yt-dlp](https://github.com/yt-dlp/yt-dlp/blob/2026.10.26/yt_dlp/postprocessor/ffmpeg.py). Le runtime a été reconstruit avec zlib/PNG et ce filtre. L’export demande une pochette JPEG. Si un traitement optionnel de pochette échoue encore, le moteur réessaie une seule fois la conversion et les tags sans pochette. Ce repli n’ignore ni DRM, ni erreur réseau, ni problème de disque, ni annulation.

## Pourquoi le Medley Stomy reste refusé

L’[upload officiel examiné](https://www.youtube.com/watch?v=ko4UaiaQ460) porte le titre « J’avance pour ma familia (Audio) » et annonce 326 secondes. Ses métadonnées complètes n’indiquent pas la version Medley ni ses invités. La proximité de durée avec les 324,093 secondes Spotify ne suffit pas à établir l’identité de la version.

Les deux références publiques Deezer examinées, [1041576](https://api.deezer.com/track/1041576) et [1041045](https://api.deezer.com/track/1041045), déclarent le Medley, l’ISRC `FRZ089602750` et une durée de **347 secondes**. Elles se trouvent sur *Le calibre qu’il te faut* et *Quelques balles de plus pour… le calibre qu’il te faut*. Ces métadonnées ne résolvent donc pas l’écart entre les versions. La source SoundCloud examinée n’expose qu’un aperçu de 30 secondes. Aucun de ces éléments ne justifie de supprimer le marqueur Medley pour compléter artificiellement la liste.

Ce refus concerne les sources inspectées à cette date ; il ne démontre pas l’absence de toute source cohérente sur Internet.

## Tests et coût observé

La première exécution avec le moteur initial a reproduit l’échec des cinq récupérations, après import réel des 61 titres. Une passe intermédiaire a validé les quatre fichiers sans pochette. Cette passe ne constitue pas une preuve de la conversion JPEG.

La passe finale avec le runtime corrigé a réussi **66 tests sur 66, sans échec ni test ignoré**, en **76,556 secondes**, le 29 octobre 2026 à 15:38:58. Elle comprend les cas contradictoires de correspondance, les notifications et la récupération complète. Chaque passe réelle crée un dossier neuf : les réussites finales ne proviennent pas d’un fichier déjà téléchargé. Le test exige aussi une vraie pochette JPEG lisible par AVFoundation.

| Morceau | Recherche, transfert complet, conversion et finalisation | Inspection supplémentaire |
| --- | ---: | ---: |
| Medley Thugs / Interlude | 16,95 s | 1 inspection, 2,51 s |
| 16'30 Contre la censure | 28,05 s | 1 inspection, 2,71 s |
| Beat de Boul est dans la sono | 11,43 s | Aucune |
| C’est donc ça nos vies | 12,82 s | Aucune |
| Medley Stomy refusé | 6,87 s | 2 inspections, 4,50 s cumulées |

Ces temps incluent le téléchargement intégral et la conversion des fichiers, dont un morceau de près de 17 minutes. Ils ne mesurent pas le délai de démarrage en streaming.

Journal final : `.tools/playlist-061/recovery-final.log`. Les vérifications FFprobe indépendantes sont enregistrées à côté de chaque fichier d’essai avec l’extension `.ffprobe.json`. Les dossiers et journaux des tentatives précédentes restent disponibles pour distinguer les erreurs reproduites des résultats finaux.

Pour réexécuter ce diagnostic depuis la racine du projet :

```sh
EASYMUSIC_PLAYLIST_RECOVERY=1 swift test --filter PlaylistRecoveryLiveTests
```

Le test embarque uniquement les cinq identifiants publics ; il récupère leurs métadonnées par `PlaylistImport.load`. Il ne lit ni ne modifie la bibliothèque de l’utilisateur. Les trois suites générales de livraison doivent également activer `EASYMUSIC_NETWORK_TESTS=1` et `EASYMUSIC_RENAUD_TEST=1`. Leur verdict relève de la clôture du rapport de cohérence général.

Les trois suites de livraison ont ensuite confirmé ces résultats : **222/222 à chaque passe, aucun échec ni test ignoré**, dans `.tools/qa-0.6.1-release-pass1.log`, `pass2.log` et `pass3.log`. La dernière s’est terminée le 29 octobre 2026 à 15:49:37,152. Le [rapport de cohérence final](COHERENCE-0.6.1.md) détaille leur matrice et leurs limites.

## Protection de la bibliothèque et limites

Le diagnostic initial a lu la bibliothèque et constaté 109 fichiers référencés, dont 56 présents dans la playlist de 61 titres. Aucune commande de ce diagnostic n’a écrit dans cette bibliothèque ni dans les fichiers musicaux utilisateur. Tous les transferts ont utilisé `.tools/playlist-061`.

À la vérification suivante, le nombre de titres et le contenu de la playlist étaient identiques. Le champ `lastSyncCheck` avait toutefois changé pendant que l’application était ouverte. Le fichier JSON ne peut donc pas être déclaré identique octet pour octet. Le test n’utilise aucun Store associé à la bibliothèque utilisateur.

La correspondance repose sur les crédits, le titre, les versions et la durée, sans empreinte audio. Les contrôles garantissent les propriétés observées des fichiers et le respect des garde-fous, sans prétendre certifier chaque enregistrement par son signal sonore. Les sources publiques peuvent évoluer ou devenir indisponibles après les essais.
