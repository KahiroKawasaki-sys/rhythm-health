import copy
import datetime as dt
import unittest
from distribute import check_distribution

class DistributionChecks(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 1, 1)
        self.bundle, self.team, self.build = "com.kawakahi.rhythm", "TESTTEAM01", "1.2.1"
        self.info = {"CFBundleIdentifier": self.bundle, "CFBundleVersion": self.build, "DTPlatformName": "iphoneos"}
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
        for ent in (self.signed, self.profile["Entitlements"]):
            ent["application-identifier"] = f"{self.team}.{self.bundle}"
            del ent["com.apple.developer.healthkit"]
            del ent["com.apple.developer.default-data-protection"]
        self.check()

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

    def test_wrong_team_build_or_platform(self):
        cases = ((self.profile, "TeamIdentifier", ["OTHERTEAM"]),
                 (self.info, "CFBundleVersion", "9"), (self.info, "DTPlatformName", "iphonesimulator"))
        for target, field, bad in cases:
            old = target[field]
            target[field] = bad
            with self.assertRaises(ValueError): self.check()
            target[field] = old

if __name__ == "__main__":
    unittest.main()
