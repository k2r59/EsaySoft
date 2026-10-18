import datetime
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cloud_signing", Path(__file__).parents[2] / "scripts/cloud-signing.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

class SigningTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 10, 18, tzinfo=datetime.timezone.utc)
        self.cert = b"public test certificate fixture"
        self.identity = hashlib.sha1(self.cert).hexdigest().upper()
        self.profile = {
            "ExpirationDate": datetime.datetime(2027, 1, 1),
            "TeamIdentifier": ["WN9MHL56A9"],
            "ApplicationIdentifierPrefix": ["WN9MHL56A9"],
            "ProvisionsAllDevices": True,
            "DeveloperCertificates": [self.cert],
            "Entitlements": {
                "com.apple.developer.aps-environment": "production",
                "com.apple.application-identifier": "WN9MHL56A9.app.easypaste.mac",
                "com.apple.developer.icloud-container-identifiers": ["iCloud.app.easypaste.mac"],
                "com.apple.developer.icloud-services": ["CloudKit"],
                "com.apple.developer.icloud-container-environment": ["Production", "Development"],
            },
        }
    def validate(self):
        return signing.validate(self.profile, self.identity, self.now)
    def test_valid_profile_exports_only_production(self):
        result = self.validate()
        self.assertEqual(result["com.apple.developer.icloud-container-environment"], "Production")
        self.assertNotIn("get-task-allow", result)
    def test_expired_profile_is_rejected(self):
        self.profile["ExpirationDate"] = self.now - datetime.timedelta(days=1)
        with self.assertRaises(ValueError): self.validate()
    def test_development_profile_is_rejected(self):
        self.profile["ProvisionsAllDevices"] = False
        with self.assertRaises(ValueError): self.validate()
    def test_other_container_is_rejected(self):
        self.profile["Entitlements"]["com.apple.developer.icloud-container-identifiers"] = ["iCloud.other"]
        with self.assertRaises(ValueError): self.validate()
    def test_unlisted_signing_certificate_is_rejected(self):
        self.profile["DeveloperCertificates"] = [b"different certificate"]
        with self.assertRaises(ValueError): self.validate()
    def test_wildcard_and_wrong_team_are_rejected(self):
        self.profile["Entitlements"]["com.apple.application-identifier"] = "WN9MHL56A9.*"
        with self.assertRaises(ValueError): self.validate()
        self.profile["TeamIdentifier"] = ["OTHER"]
        with self.assertRaises(ValueError): self.validate()
    def test_development_environment_only_is_rejected(self):
        self.profile["Entitlements"]["com.apple.developer.icloud-container-environment"] = ["Development"]
        with self.assertRaises(ValueError): self.validate()
    def test_missing_remote_notifications_is_rejected(self):
        del self.profile["Entitlements"]["com.apple.developer.aps-environment"]
        with self.assertRaises(ValueError): self.validate()

if __name__ == "__main__": unittest.main()
