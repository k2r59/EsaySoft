# EasyMusic 0.3.0

- Import de playlists publiques Spotify, Deezer et YouTube Music depuis un lien.
- Playlist locale persistante, ordre conservé, titres déjà présents réutilisés et téléchargement des titres manquants.
- Échecs visibles par titre et possibilité de réessayer.
- Accueil généraliste qui s’adapte aux recherches et aux écoutes.
- Lecteur avec file, répétition, lecture aléatoire, volume et sortie audio.
- Mises à jour Sparkle signées, distribuées sur le dépôt EsaySoft.

Spotify : l’import utilise la page publique, dont la liste peut être limitée. L’exhaustivité n’est pas garantie et un avertissement apparaît dans la playlist. Les fichiers audio sont recherchés sur les sources accessibles, pas téléchargés depuis Spotify. Les playlists privées et les liens courts ne sont pas pris en charge.

Application universelle Intel et Apple Silicon, macOS 13 minimum. yt-dlp, FFmpeg, FFprobe et Node.js inclus.

Validation : 43 tests, dont 15 tests réseau ; imports réels sur les trois plateformes vérifiés.
