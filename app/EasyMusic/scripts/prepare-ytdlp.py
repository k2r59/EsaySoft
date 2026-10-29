#!/usr/bin/env python3
"""Prepare the verified official onedir runtime once, avoiding per-launch unpacking."""
import hashlib
import pathlib
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "2026.10.26"
SHA256 = "20d98fa608998eff87d1d35a6e9fb65e4b874639a6cc89addc19da3becde3ef1"
archive = ROOT / ".tools/vendor/yt-dlp_macos.zip"
runtime = ROOT / ".tools/runtime/yt-dlp-runtime"
archive.parent.mkdir(parents=True, exist_ok=True)
runtime.parent.mkdir(parents=True, exist_ok=True)
if not archive.exists():
    with urllib.request.urlopen(f"https://github.com/yt-dlp/yt-dlp/releases/download/{VERSION}/yt-dlp_macos.zip", timeout=60) as response:
        with archive.open("wb") as output:
            shutil.copyfileobj(response, output)
if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    raise RuntimeError("L’archive yt-dlp ne correspond pas à la somme officielle attendue.")
marker = runtime / ".verified-sha256"
if not marker.exists() or marker.read_text().strip() != SHA256:
    with tempfile.TemporaryDirectory(prefix="ytdlp-", dir=runtime.parent) as folder:
        staged = pathlib.Path(folder) / "runtime"
        subprocess.run(["ditto", "-x", "-k", str(archive), str(staged)], check=True)
        # The release ZIP stores framework aliases as copies. Restore the standard
        # versioned framework layout before Developer ID signing.
        internal = staged / "_internal"
        framework = internal / "Python.framework"
        version = framework / "Versions/3.14"
        for duplicate in [internal / "Python", framework / "Python", framework / "Versions/Current/Python"]:
            if duplicate.read_bytes() != (version / "Python").read_bytes():
                raise RuntimeError("Copies Python incohérentes dans l’archive officielle.")
        shutil.rmtree(framework / "Versions/Current")
        (framework / "Versions/Current").symlink_to("3.14", target_is_directory=True)
        (framework / "Python").unlink()
        (framework / "Python").symlink_to("Versions/Current/Python")
        shutil.rmtree(framework / "Resources")
        (framework / "Resources").symlink_to("Versions/Current/Resources", target_is_directory=True)
        (internal / "Python").unlink()
        (internal / "Python").symlink_to("Python.framework/Versions/Current/Python")
        (staged / ".verified-sha256").write_text(SHA256 + "\n")
        if runtime.exists():
            shutil.rmtree(runtime)
        shutil.move(str(staged), runtime)
print(f"yt-dlp {VERSION} : runtime déployé et vérifié")
