#!/usr/bin/env python3
"""Check that incomplete or insecure release settings never reach a signed app."""
import base64
import importlib.util
import plistlib
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("configuration", Path(__file__).with_name("configure-updates.py"))
configuration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configuration)


class UpdateConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.info = {"CFBundleIdentifier": "local.notch.mac", "CFBundleVersion": "20"}
        self.env = {"NOTCH_UPDATE_FEED_URL": "https://example.com/appcast.xml",
                    "NOTCH_SPARKLE_PUBLIC_KEY": base64.b64encode(bytes(range(32))).decode()}

    def test_local_build_remains_unconfigured_and_identity_is_unchanged(self):
        self.assertEqual(configuration.configure(self.info, {}), self.info)
        result = configuration.configure(self.info, self.env)
        self.assertEqual(result["CFBundleIdentifier"], self.info["CFBundleIdentifier"])
        self.assertEqual(result["CFBundleVersion"], "20")
        self.assertEqual(result["SUPublicEDKey"], self.env["NOTCH_SPARKLE_PUBLIC_KEY"])
        self.assertNotIn("SUFeedURL", self.info)

    def test_partial_configuration_and_missing_public_configuration_fail(self):
        for env in [{"NOTCH_PUBLIC_RELEASE": "1"},
                    {"NOTCH_UPDATE_FEED_URL": self.env["NOTCH_UPDATE_FEED_URL"]},
                    {"NOTCH_SPARKLE_PUBLIC_KEY": self.env["NOTCH_SPARKLE_PUBLIC_KEY"]}]:
            with self.assertRaises(ValueError):
                configuration.configure(self.info, env)

    def test_insecure_urls_and_malformed_keys_fail(self):
        for url in ["http://example.com", "file:///tmp/feed", "https://user:pass@example.com", "https://example.com/#anchor", "https://example.com/a b"]:
            with self.assertRaises(ValueError):
                configuration.configure(self.info, dict(self.env, NOTCH_UPDATE_FEED_URL=url))
        for key in ["", "invalid", base64.b64encode(bytes(31)).decode(), base64.b64encode(bytes(64)).decode()]:
            with self.assertRaises(ValueError):
                configuration.configure(self.info, dict(self.env, NOTCH_SPARKLE_PUBLIC_KEY=key))

    def test_shipping_policy_defaults_to_verified_automatic_updates(self):
        info = plistlib.loads((Path(__file__).resolve().parent.parent / "Resources/Info.plist").read_bytes())
        self.assertTrue(info["SUEnableAutomaticChecks"])
        self.assertTrue(info["SUAutomaticallyUpdate"])
        self.assertEqual(info["SUScheduledCheckInterval"], 3600)
        self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])
        self.assertTrue(info["SURequireSignedFeed"])
        self.assertFalse(info["SUEnableSystemProfiling"])
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)


if __name__ == "__main__":
    unittest.main()
