# Composants tiers

Le système de mise à jour est adapté de EasyPaste (EsaySoft), sous licence MIT reproduite dans EsaySoft-LICENSE.txt.

- Sparkle 2.10.0 : licence incluse dans l’application.
- yt-dlp 2026.10.26 : binaire autonome officiel ; https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26. Ses dépendances possèdent leurs propres licences.
- FFmpeg 8.1.2 et LAME 3.100 : LGPL 2.1 ou ultérieure. Sources exactes et script de compilation fournis dans l’archive sources. Ce build n’active aucun composant GPL de FFmpeg.
- Node.js 22.23.4 : licence MIT et licences de ses dépendances incluses dans l’application.

FFmpeg et LAME sont des programmes séparés, compilés statiquement. Le script build-dependencies.sh permet de les reconstruire, les modifier et les remplacer ; les archives sources permettent de reconstruire les exécutables complets.
