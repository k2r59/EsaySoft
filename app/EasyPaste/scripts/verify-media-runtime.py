#!/usr/bin/env python3
"""Verify packaged helpers without Homebrew, EasyMusic or user configuration."""
import pathlib
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
resources = app / "Contents/Resources"
tools = resources / "bin"
magic = {bytes.fromhex(v) for v in ["feedface", "feedfacf", "cefaedfe", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"]}
count = 0
for path in tools.rglob("*"):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        if stream.read(4) not in magic:
            continue
    for arch in ["arm64", "x86_64"]:
        subprocess.run(["lipo", str(path), "-verify_arch", arch], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(path)], check=True)
    linked = subprocess.check_output(["otool", "-L", str(path)], text=True)
    for line in linked.splitlines():
        if not line.startswith("\t"):
            continue
        dependency = line.strip().split(" (", 1)[0]
        if not dependency.startswith(("@", "/usr/lib/", "/System/Library/")):
            raise RuntimeError(f"External library dependency: {path.name}: {dependency}")
    count += 1

with tempfile.TemporaryDirectory(prefix="EasyPaste-runtime-check-") as home:
    environment = {"HOME": home, "PATH": "/usr/bin:/bin", "TMPDIR": home, "LANG": "en_US.UTF-8"}
    for relative, args in [("yt-dlp-runtime/yt-dlp_macos", ["--ignore-config", "--no-plugin-dirs", "--no-js-runtimes", "--version"]),
                           ("ffmpeg", ["-version"]), ("ffprobe", ["-version"]), ("node", ["--version"])]:
        result = subprocess.run([str(tools / relative), *args], env=environment, cwd=home,
                                check=True, capture_output=True, text=True, timeout=30)
        print(relative + ": " + result.stdout.splitlines()[0])
for name in ["yt-dlp.txt", "yt-dlp-LICENSE.txt", "FFmpeg-LGPL.txt", "LAME-LGPL.txt", "Node-LICENSE.txt"]:
    assert (resources / "Licenses" / name).stat().st_size > 0, name
print(f"Verified {count} universal signed native components; no external library dependencies.")
