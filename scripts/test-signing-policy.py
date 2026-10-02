#!/usr/bin/env python3
import unittest
from signing_policy import host_entitlements


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.base = {"com.apple.security.automation.apple-events": True}
        self.exception = "com.apple.security.cs.disable-library-validation"

    def test_local_exception_requires_explicit_approval(self):
        with self.assertRaises(ValueError):
            host_entitlements(self.base, local_identity=True, public_release=False, allow_local_sparkle=False)
        result = host_entitlements(self.base, local_identity=True, public_release=False, allow_local_sparkle=True)
        self.assertTrue(result[self.exception])
        self.assertTrue(result["com.apple.security.automation.apple-events"])
        self.assertNotIn(self.exception, self.base)

    def test_apple_signed_build_keeps_library_validation(self):
        result = host_entitlements(self.base, local_identity=False, public_release=True, allow_local_sparkle=False)
        self.assertEqual(result, self.base)

    def test_public_release_rejects_personal_exception(self):
        with self.assertRaises(ValueError):
            host_entitlements(self.base, local_identity=False, public_release=True, allow_local_sparkle=True)
        with self.assertRaises(ValueError):
            host_entitlements(dict(self.base, **{self.exception: True}), local_identity=False, public_release=True, allow_local_sparkle=False)


if __name__ == "__main__":
    unittest.main()
