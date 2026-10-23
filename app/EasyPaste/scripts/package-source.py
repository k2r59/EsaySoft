#!/usr/bin/env python3
"""Export buildable sources without macOS metadata or generated dependencies."""
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
files = ["Package.swift", "Package.resolved", "LICENSE", "README.md",
         "THIRD-PARTY-NOTICES.md", "ASSET-PROMPT.txt", ".gitignore"]
files += sorted(path.name for path in ROOT.glob("QA-*.md"))
ignore = shutil.ignore_patterns("node_modules", "dist", "__pycache__", "*.zip", ".DS_Store", "._*")
with tempfile.TemporaryDirectory(prefix="EasyPaste-source-") as directory:
    source = Path(directory) / "EasyPaste-source"
    source.mkdir()
    for name in files:
        shutil.copy(ROOT / name, source / name)
    for name in ("Sources", "Tests", "scripts", "docs", "BrowserExtension"):
        if (ROOT / name).is_dir():
            shutil.copytree(ROOT / name, source / name, ignore=ignore, copy_function=shutil.copy)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(source.parent).as_posix())
print(f"Sources : {output}")
