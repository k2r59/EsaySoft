#!/usr/bin/env python3
"""Validate an Apple Developer ID profile and produce the matching CloudKit entitlements."""
import datetime
import hashlib
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def validate(profile, identity, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiration = profile.get("ExpirationDate")
    if expiration is None or expiration.replace(tzinfo=datetime.timezone.utc) <= now:
        raise ValueError("Le profil Apple est absent ou expiré.")
    if profile.get("ProvisionsAllDevices") is not True:
        raise ValueError("Un profil de distribution Developer ID est nécessaire pour le DMG.")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("Un profil de développement ne convient pas à la distribution.")
    team = "WN9MHL56A9"
    container = "iCloud.app.easypaste.mac"
    if team not in profile.get("TeamIdentifier", []):
        raise ValueError("Le profil n’appartient pas à l’équipe Les papas du code.")
    app_id = entitlements.get("com.apple.application-identifier", "")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if not any(app_id == prefix + ".app.easypaste.mac" for prefix in prefixes):
        raise ValueError("Le profil doit cibler explicitement app.easypaste.mac.")
    if container not in entitlements.get("com.apple.developer.icloud-container-identifiers", []):
        raise ValueError("Le conteneur iCloud d’EasyPaste n’est pas autorisé par ce profil.")
    if "CloudKit" not in entitlements.get("com.apple.developer.icloud-services", []):
        raise ValueError("CloudKit n’est pas activé dans ce profil.")
    environments = entitlements.get("com.apple.developer.icloud-container-environment", [])
    if isinstance(environments, str):
        environments = [environments]
    if "Production" not in environments:
        raise ValueError("Le profil ne permet pas l’environnement iCloud Production.")
    if entitlements.get("com.apple.developer.aps-environment") != "production":
        raise ValueError("Le profil doit autoriser les notifications distantes en production pour CKSyncEngine.")
    certs = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
    if identity.upper() not in certs:
        raise ValueError("Le certificat de signature n’est pas inclus dans le profil Apple.")
    return {
        "com.apple.security.device.audio-input": True,
        "com.apple.developer.aps-environment": "production",
        "com.apple.application-identifier": app_id,
        "com.apple.developer.team-identifier": team,
        "com.apple.developer.icloud-container-identifiers": [container],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-environment": "Production",
    }


def main():
    if len(sys.argv) != 4:
        raise ValueError("Usage : cloud-signing.py profil.provisionprofile identité sortie.entitlements")
    profile_path, requested_identity, output = sys.argv[1:]
    raw = subprocess.check_output(["security", "cms", "-D", "-i", profile_path], stderr=subprocess.DEVNULL)
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    matches = re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
    hashes = [fingerprint for fingerprint, name in matches if requested_identity in (fingerprint, name) and name.startswith("Developer ID Application:")]
    if len(hashes) != 1:
        raise ValueError("Choisis une identité Developer ID Application unique et valide.")
    entitlements = validate(plistlib.loads(raw), hashes[0])
    Path(output).write_bytes(plistlib.dumps(entitlements))
    print("Profil Developer ID validé pour EasyPaste et iCloud Production.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"Configuration iCloud : {error}")
