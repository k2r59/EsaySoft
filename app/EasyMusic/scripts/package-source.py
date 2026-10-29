#!/usr/bin/env python3
"""Archive reproductible sans données utilisateur ni identifiants."""
import pathlib
import sys
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in ['Sources', 'Tests', 'scripts', 'docs', '.gitignore', 'Package.swift', 'Package.resolved', 'README.md', 'THIRD-PARTY-NOTICES.md', 'EsaySoft-LICENSE.txt']:
        path = root / name
        for item in sorted(path.rglob('*')) if path.is_dir() else [path]:
            if item.is_file() and '__pycache__' not in item.parts:
                archive.write(item, 'EasyMusic/' + str(item.relative_to(root)))
    for name in ['ffmpeg-8.1.2.tar.gz', 'lame-3.100.tar.gz', 'yt-dlp-THIRD-PARTY-LICENSES.txt']:
        item = root / '.tools/vendor' / name
        archive.write(item, 'EasyMusic/.tools/vendor/' + name)
