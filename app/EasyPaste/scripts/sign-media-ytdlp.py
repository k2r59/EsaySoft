#!/usr/bin/env python3
"""Sign every Mach-O in the bundled runtime, then its framework and launcher."""
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
identity = os.environ.get("CODE_SIGN_IDENTITY", "-")
args = ["codesign", "--force", "--sign", identity]
if identity != "-":
    args += ["--options", "runtime", "--timestamp"]
magic = {bytes.fromhex(value) for value in ["feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"]}
launcher = root / "yt-dlp_macos"
count = 0
for path in sorted(root.rglob("*")):
    if path.is_symlink() or not path.is_file() or path == launcher:
        continue
    with path.open("rb") as handle:
        native = handle.read(4) in magic
    if native:
        subprocess.run(args + [str(path)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        count += 1
framework = root / "_internal/Python.framework"
subprocess.run(args + [str(framework)], check=True)
# All native extensions now share our Developer ID; no library-validation bypass is needed.
subprocess.run(args + [str(launcher)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(framework)], check=True)
print(f"yt-dlp : {count} composants natifs, framework et lanceur signés")
