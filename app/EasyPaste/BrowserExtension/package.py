#!/usr/bin/env python3
"""Build a local, dependency-free unpacked-extension ZIP. Never publishes."""
import argparse
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent
version = json.loads((root / "manifest.json").read_text())["version"]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=Path.home() / "Library/Caches/EasyPaste-extension-tests" / f"EasyPaste-Web-{version}.zip")
args = parser.parse_args()
files = [root / name for name in ("manifest.json", "popup.html", "popup.css", "popup.js", "README.md", "QA.md", "LICENSE")]
files += sorted((root / "src").glob("*.js")) + sorted((root / "icons").glob("*.png"))
args.output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(args.output, "w", compression=ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, Path("EasyPaste-Web") / path.relative_to(root))
with ZipFile(args.output) as archive:
    assert archive.testzip() is None
print(f"{args.output} ({args.output.stat().st_size} bytes, {len(files)} files)")
