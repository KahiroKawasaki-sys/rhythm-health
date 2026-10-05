import copy
import datetime as dt
import unittest
from distribute import check_distribution, normalize_private_key

class DistributionChecks(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 1, 1)
        self.bundle, self.team, self.build = "com.kawakahi.rhythm", "TESTTEAM01", "1.2.1"
        self.info = {"CFBundleIdentifier": self.bundle, "CFBundleVersion": self.build, "DTPlatformName": "iphoneos"}
        self.info.update({"NSHealthShareUsageDescription": "Read records for review", "NSHealthUpdateUsageDescription": "Read only; no writes"})
        self.signed = {"application-identifier": f"{self.team}.{self.bundle}",
                       "com.apple.developer.team-identifier": self.team,
                       "get-task-allow": False,
                       "com.apple.developer.family-controls": True,
                       "com.apple.developer.healthkit": True,
                       "com.apple.developer.default-data-protection": "NSFileProtectionComplete"}
        self.profile = {"ExpirationDate": self.now + dt.timedelta(days=5),
                        "TeamIdentifier": [self.team], "Entitlements": copy.deepcopy(self.signed)}

    def check(self):
        check_distribution(self.info, self.signed, self.profile, self.bundle, self.team, self.build, self.now)

    def test_valid_distribution(self):
        self.check()

    def test_extension_does_not_require_healthkit(self):
        self.bundle += ".ScreenTimeReport"
        self.info["CFBundleIdentifier"] = self.bundle
        self.info["EXAppExtensionAttributes"] = {"EXExtensionPointIdentifier": "com.apple.deviceactivityui.report-extension"}
        for ent in (self.signed, self.profile["Entitlements"]):
            ent["application-identifier"] = f"{self.team}.{self.bundle}"
            del ent["com.apple.developer.healthkit"]
            del ent["com.apple.developer.default-data-protection"]
        self.check()

    def test_legacy_report_metadata_is_rejected(self):
        self.test_extension_does_not_require_healthkit()
        self.info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.deviceactivityui.report-extension"}
        with self.assertRaises(ValueError): self.check()

    def test_missing_family_controls_on_either_side(self):
        for target in (self.signed, self.profile["Entitlements"]):
            target["com.apple.developer.family-controls"] = False
            with self.assertRaises(ValueError): self.check()
            target["com.apple.developer.family-controls"] = True

    def test_wrong_app_identifier(self):
        self.signed["application-identifier"] = "OTHERTEAM.com.unrelated.app"
        with self.assertRaises(ValueError): self.check()

    def test_expired_profile(self):
        self.profile["ExpirationDate"] = self.now
        with self.assertRaises(ValueError): self.check()

    def test_development_or_enterprise_profile(self):
        for field, value in (("ProvisionedDevices", ["device"]), ("ProvisionsAllDevices", True)):
            self.profile[field] = value
            with self.assertRaises(ValueError): self.check()
            del self.profile[field]

    def test_debugging_enabled(self):
        self.profile["Entitlements"]["get-task-allow"] = True
        with self.assertRaises(ValueError): self.check()

    def test_missing_healthkit_or_data_protection(self):
        for field in ("com.apple.developer.healthkit", "com.apple.developer.default-data-protection"):
            old = self.signed.pop(field)
            with self.assertRaises(ValueError): self.check()
            self.signed[field] = old

    def test_missing_healthkit_purpose_is_rejected(self):
        del self.info["NSHealthUpdateUsageDescription"]
        with self.assertRaises(ValueError): self.check()

    def test_wrong_team_build_or_platform(self):
        cases = ((self.profile, "TeamIdentifier", ["OTHERTEAM"]),
                 (self.info, "CFBundleVersion", "9"), (self.info, "DTPlatformName", "iphonesimulator"))
        for target, field, bad in cases:
            old = target[field]
            target[field] = bad
            with self.assertRaises(ValueError): self.check()
            target[field] = old


class KeyTextChecks(unittest.TestCase):
    # Synthetic format fixtures only; these are not cryptographic keys.
    SAMPLE = "-----BEGIN PRIVATE KEY-----\nMAMCAQE=\n-----END PRIVATE KEY-----\n"

    def test_plain_text(self):
        self.assertEqual(normalize_private_key(self.SAMPLE), self.SAMPLE)

    def test_windows_bom_and_line_endings(self):
        self.assertEqual(normalize_private_key("\ufeff" + self.SAMPLE.replace("\n", "\r\n")), self.SAMPLE)

    def test_format_error_does_not_reveal_value(self):
        sentinel = "PRIVATE_VALUE_MUST_NEVER_APPEAR"
        with self.assertRaises(ValueError) as caught:
            normalize_private_key(sentinel)
        self.assertNotIn(sentinel, str(caught.exception))
        self.assertIn("No contents logged", str(caught.exception))

    def test_base64_only_gets_pem_wrapper(self):
        self.assertEqual(normalize_private_key("MAMC\nAQE="), self.SAMPLE)

    def test_random_base64_is_not_key_data(self):
        with self.assertRaises(ValueError): normalize_private_key("aGVsbG8=")

    def test_rejects_path_and_incomplete_text(self):
        for value in ("C:/Downloads/AuthKey_example.p8", "AuthKey_example.p8", "-----BEGIN PRIVATE KEY-----", ""):
            with self.assertRaises(ValueError): normalize_private_key(value)

if __name__ == "__main__":
    unittest.main()
