#!/usr/bin/env python3
"""Publish a notarized EasyPaste release, then atomically advance its signed feed.

Run after tests + package.sh, from a clean, pushed source commit.
Private signing keys stay in the macOS Keychain. No credentials enter GitHub.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "k2r59/EsaySoft"
NS = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


def run(*args, input=None):
    return subprocess.check_output(args, cwd=ROOT, input=input, text=True).strip()


def api(path, data=None, missing=False, method=None):
    args = ["gh", "api", f"repos/{REPO}/{path}"]
    if method:
        args += ["--method", method]
    if data is not None:
        args += ["--input", "-"]
    proc = subprocess.run(args, cwd=ROOT, input=json.dumps(data) if data is not None else None,
                          text=True, capture_output=True)
    if proc.returncode:
        if missing and "(HTTP 404)" in proc.stderr:
            return None
        raise RuntimeError(proc.stderr)
    return json.loads(proc.stdout) if proc.stdout else None


def deploy(feed):
    old = api("git/ref/heads/gh-pages", missing=True)
    parent = old["object"]["sha"] if old else None
    base_tree = api(f"git/commits/{parent}")["tree"]["sha"] if parent else None
    tree = [
        {"path": "easypaste/appcast.xml", "mode": "100644", "type": "blob",
         "content": feed.decode("utf-8")},
        {"path": ".nojekyll", "mode": "100644", "type": "blob", "content": ""},
        {"path": "index.html", "mode": "100644", "type": "blob",
         "content": '<!doctype html><html lang="fr"><meta charset="utf-8"><title>EasySoft</title>'
                    '<p>Mises à jour EasySoft. <a href="https://github.com/k2r59/EsaySoft/releases">'
                    'Télécharger les applications</a>.</p></html>'}
    ]
    body = {"tree": tree}
    if base_tree:
        body["base_tree"] = base_tree
    tree_sha = api("git/trees", body)["sha"]
    commit = api("git/commits", {"message": "Publish signed EasyPaste update feed",
                               "tree": tree_sha, "parents": [parent] if parent else []})
    if parent:
        api("git/refs/heads/gh-pages", {"sha": commit["sha"], "force": False}, method="PATCH")
    else:
        api("git/refs", {"ref": "refs/heads/gh-pages", "sha": commit["sha"]})
    if api("pages", missing=True) is None:
        try:
            api("pages", {"source": {"branch": "gh-pages", "path": "/"}})
        except RuntimeError as error:
            # GitHub can enable Pages automatically when gh-pages first appears.
            if "(HTTP 409)" not in str(error):
                raise
    source = api("pages").get("source", {})
    if source != {"branch": "gh-pages", "path": "/"}:
        raise RuntimeError("GitHub Pages utilise une autre source. Ne pas la remplacer automatiquement.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes", required=True, type=pathlib.Path)
    parser.add_argument("--publish", action="store_true", help="Publier après vérification locale")
    parser.add_argument("--prerelease", action="store_true", help="Marquer les premiers essais comme préversion")
    args = parser.parse_args()
    config = json.loads((ROOT / "scripts/release.json").read_text())
    version, build = config["version"], config["build"]
    tag = f"easypaste-v{version}"
    dist = ROOT / "dist"
    app = dist / f"EasyPaste-{version}.app"
    dmg = dist / f"EasyPaste-{version}-universal.dmg"
    assets = [dmg, dist / f"EasyPaste-{version}-universal.zip",
              dist / f"EasyPaste-{version}-source.zip", dist / "SHA256SUMS"]
    for asset in assets:
        if not asset.is_file():
            raise RuntimeError(f"Fichier absent : {asset}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleVersion"] == build and info["CFBundleShortVersionString"] == version
    assert info["SUFeedURL"] == config["feed"] and info["SUPublicEDKey"] == config["publicKey"]
    assert info["SURequireSignedFeed"] and info["SUVerifyUpdateBeforeExtraction"]
    assert not info.get("EasyPasteDemo") and not info.get("EasyPasteUpdateQA") and not info.get("AnnotationPreview")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    run("spctl", "--assess", "--type", "execute", str(app))
    run("xcrun", "stapler", "validate", str(dmg))
    run("codesign", "--verify", str(dmg))
    for line in (dist / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        assert hashlib.sha256((dist / name.strip()).read_bytes()).hexdigest() == digest
    if args.publish:
        if run("git", "status", "--porcelain"):
            raise RuntimeError("Commiter les sources avant la publication.")
        sha = run("git", "rev-parse", "HEAD")
        # The code must exist remotely before a release can point at it.
        api(f"commits/{sha}")
        pages = api("pages", missing=True)
        if pages and pages.get("source") != {"branch": "gh-pages", "path": "/"}:
            raise RuntimeError("La source GitHub Pages existante est différente.")
    with tempfile.TemporaryDirectory(prefix="EasyPaste-appcast-") as folder:
        folder = pathlib.Path(folder)
        feed = folder / "appcast.xml"
        try:
            with urllib.request.urlopen(config["feed"], timeout=30) as response:
                previous = response.read()
            previous_builds = ET.fromstring(previous).findall(".//s:version", NS)
            if previous_builds and int(build) <= max(int(v.text) for v in previous_builds):
                raise RuntimeError("Le numéro de build doit augmenter. Ne jamais remplacer une version publiée.")
            feed.write_bytes(previous)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
        # Copy only the OTA DMG; never sign a source archive as an application update.
        import shutil
        shutil.copy2(dmg, folder / dmg.name)
        (folder / f"{dmg.stem}.md").write_text(args.notes.read_text())
        tools = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
        run(str(tools / "generate_appcast"), "--account", config["keychainAccount"],
            "--maximum-deltas", "0", "--embed-release-notes",
            "--download-url-prefix", f"https://github.com/{REPO}/releases/download/{tag}/",
            str(folder))
        contents = feed.read_bytes()
        root = ET.fromstring(contents)
        item = next(i for i in root.findall("./channel/item") if i.findtext("s:version", namespaces=NS) == build)
        enclosure = item.find("enclosure")
        assert enclosure.attrib["url"] == f"https://github.com/{REPO}/releases/download/{tag}/{dmg.name}"
        assert int(enclosure.attrib["length"]) == dmg.stat().st_size
        assert len(base64.b64decode(enclosure.attrib[f"{{{NS['s']}}}edSignature"])) == 64
        assert b"edSignature" in contents and b"<!--" in contents
        verify = str(ROOT / "scripts/verify-update.swift")
        run("swift", verify, config["publicKey"], str(feed))
        run("swift", verify, config["publicKey"], str(dmg),
            enclosure.attrib[f"{{{NS['s']}}}edSignature"])
        output = dist / "appcast.xml"
        output.write_bytes(contents)
        print(f"Flux signé prêt : {output}")
        if not args.publish:
            return
        existing = api(f"releases/tags/{tag}", missing=True)
        if existing:
            raise RuntimeError("Cette release existe déjà. Vérifier son état avant de reprendre.")
        run("gh", "release", "create", tag, "--repo", REPO, "--target", sha,
            "--draft", "--title", f"EasyPaste {version}", "--notes-file", str(args.notes.resolve()),
            *(["--prerelease"] if args.prerelease else []),
            *(str(a) for a in assets))
        # Verify every uploaded asset before exposing the feed to installed apps.
        with tempfile.TemporaryDirectory(prefix="EasyPaste-release-check-") as downloaded:
            run("gh", "release", "download", tag, "--repo", REPO, "--dir", downloaded)
            for asset in assets:
                assert hashlib.sha256(asset.read_bytes()).digest() == hashlib.sha256(
                    (pathlib.Path(downloaded) / asset.name).read_bytes()).digest()
        run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false")
        deploy(contents)
        print(f"Release publiée : https://github.com/{REPO}/releases/tag/{tag}")
        print(f"Attendre le déploiement GitHub Pages puis vérifier : {config['feed']}")


if __name__ == "__main__":
    main()
