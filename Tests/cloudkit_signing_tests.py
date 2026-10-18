#!/usr/bin/env python3
"""Cloud-Builds müssen fremde, abgelaufene und unpassende Profile ablehnen."""
import copy
import datetime
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cloudkit_signing", Path(__file__).resolve().parents[1] / "tools/prepare-cloudkit.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.certificate = b"synthetic-certificate"
        self.identity = hashlib.sha1(self.certificate).hexdigest().upper()
        self.container = "iCloud.example.Player"
        self.profile = {
            "TeamIdentifier": ["EXAMPLE"], "Platform": ["OSX"],
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
            "DeveloperCertificates": [self.certificate],
            "Entitlements": {
                "com.apple.application-identifier": "EXAMPLE.example.Player",
                "com.apple.developer.icloud-container-identifiers": [self.container],
                "com.apple.developer.icloud-services": "*",
                "com.apple.developer.icloud-container-environment": ["Development", "Production"],
            },
        }

    def validate(self, profile=None, environment="Development", identities=None):
        return signing.validate(profile or self.profile, "macos", "EXAMPLE", "example.Player", self.container,
                                environment, identities if identities is not None else {self.identity})

    def test_valid_profile_requests_only_cloudkit_and_one_container(self):
        identity, entitlements = self.validate()
        self.assertEqual(identity, self.identity)
        self.assertEqual(entitlements["com.apple.developer.icloud-services"], ["CloudKit"])
        self.assertEqual(entitlements["com.apple.developer.icloud-container-identifiers"], [self.container])
        self.assertNotIn("get-task-allow", entitlements)
        self.assertNotIn("keychain-access-groups", entitlements)

    def test_rejects_wrong_team_platform_and_wildcard_app_id(self):
        for key, value in [("TeamIdentifier", ["OTHER"]), ("Platform", ["iOS"])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                profile = copy.deepcopy(self.profile)
                profile[key] = value
                self.validate(profile)
        profile = copy.deepcopy(self.profile)
        profile["Entitlements"]["com.apple.application-identifier"] = "EXAMPLE.*"
        with self.assertRaises(ValueError):
            self.validate(profile)

    def test_rejects_other_or_additional_containers(self):
        for containers in [[], ["iCloud.other.Player"], [self.container, "iCloud.other.Player"]]:
            with self.subTest(containers=containers), self.assertRaises(ValueError):
                profile = copy.deepcopy(self.profile)
                profile["Entitlements"]["com.apple.developer.icloud-container-identifiers"] = containers
                self.validate(profile)

    def test_rejects_missing_service_and_wrong_environment(self):
        profile = copy.deepcopy(self.profile)
        profile["Entitlements"]["com.apple.developer.icloud-services"] = ["CloudDocuments"]
        with self.assertRaises(ValueError):
            self.validate(profile)
        profile = copy.deepcopy(self.profile)
        profile["Entitlements"]["com.apple.developer.icloud-container-environment"] = "Production"
        with self.assertRaises(ValueError):
            self.validate(profile)
        self.assertEqual(self.validate(profile, environment="Production")[1]["com.apple.developer.icloud-container-environment"], "Production")

    def test_rejects_expired_profile_or_unavailable_signing_key(self):
        profile = copy.deepcopy(self.profile)
        profile["ExpirationDate"] = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)
        with self.assertRaises(ValueError):
            self.validate(profile)
        with self.assertRaises(ValueError):
            self.validate(identities=set())


if __name__ == "__main__":
    unittest.main()
