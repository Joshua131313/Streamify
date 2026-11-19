"""Portable signing fixtures. Never contacts Apple or uses real signing material."""
import base64
import copy
import datetime as dt
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

from testflight_signing import (SigningError, build_configuration, cleanup, private_write,
                               read_certificate, validate_environment, validate_profile, verify_identity)


TEAM = "AB12CD34EF"
BUNDLE = "com.streamify.app"
WIDGET = BUNDLE + ".widgets"
CERTIFICATE = b"fixture-distribution-certificate"
APP_PROFILE = "11111111-1111-1111-1111-111111111111"
WIDGET_PROFILE = "22222222-2222-2222-2222-222222222222"
NOW = dt.datetime(2026, 11, 19, tzinfo=dt.timezone.utc)


def profile(bundle=BUNDLE, profile_id=APP_PROFILE):
    return {
        "UUID": profile_id, "TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [TEAM],
        "Entitlements": {"application-identifier": TEAM + "." + bundle,
                         "com.apple.developer.team-identifier": TEAM, "get-task-allow": False},
        "ExpirationDate": dt.datetime(2027, 11, 19),
        "Platform": ["iOS"], "DeveloperCertificates": [CERTIFICATE],
    }


def environment():
    encoded = base64.b64encode(b"fixture-material").decode("ascii")
    return {
        "IOS_TEAM_ID": TEAM, "IOS_BUNDLE_ID": BUNDLE, "IOS_BUILD_NUMBER": "196",
        "IOS_CERTIFICATE_P12_BASE64": encoded, "IOS_CERTIFICATE_PASSWORD": "fixture-password",
        "IOS_PROFILE_BASE64": encoded, "IOS_WIDGET_PROFILE_BASE64": encoded,
    }


class ProfileTests(unittest.TestCase):
    def check(self, fixture, bundle=BUNDLE):
        return validate_profile(fixture, TEAM, bundle, CERTIFICATE, "Fixture", now=NOW)

    def test_valid_app_and_widget_profiles_survive_plist_roundtrip(self):
        for bundle, identifier in ((BUNDLE, APP_PROFILE), (WIDGET, WIDGET_PROFILE)):
            decoded = plistlib.loads(plistlib.dumps(profile(bundle, identifier)))
            self.assertEqual(self.check(decoded, bundle), identifier)

    def test_legacy_app_identifier_prefix_can_differ_from_team(self):
        fixture = profile()
        fixture["ApplicationIdentifierPrefix"] = ["LEGACY1234"]
        fixture["Entitlements"]["application-identifier"] = "LEGACY1234." + BUNDLE
        self.assertEqual(self.check(fixture), APP_PROFILE)

    def test_rejects_wrong_team_or_entitlement_team(self):
        for key in ("TeamIdentifier", "com.apple.developer.team-identifier"):
            with self.subTest(key=key):
                fixture = profile()
                if key == "TeamIdentifier":
                    fixture[key] = ["WRONG12345"]
                else:
                    fixture["Entitlements"][key] = "WRONG12345"
                with self.assertRaisesRegex(SigningError, "team"):
                    self.check(fixture)

    def test_rejects_wrong_bundle_wildcard_and_unlisted_prefix(self):
        for identifier in (TEAM + "." + WIDGET, TEAM + ".*", "UNKNOWN123." + BUNDLE):
            with self.subTest(identifier=identifier):
                fixture = profile()
                fixture["Entitlements"]["application-identifier"] = identifier
                with self.assertRaisesRegex(SigningError, "exact bundle"):
                    self.check(fixture)

    def test_rejects_expired_or_missing_expiration(self):
        for expiration in (NOW.replace(tzinfo=None), NOW - dt.timedelta(seconds=1), None):
            with self.subTest(expiration=expiration):
                fixture = {**profile(), "ExpirationDate": expiration}
                with self.assertRaises(SigningError):
                    self.check(fixture)

    def test_rejects_development_adhoc_and_enterprise_profiles(self):
        for mutation in ({"ProvisionedDevices": ["fixture-device"]}, {"ProvisionedDevices": []},
                         {"ProvisionsAllDevices": True}, {"get-task-allow": True}):
            with self.subTest(mutation=mutation):
                fixture = profile()
                if "get-task-allow" in mutation:
                    fixture["Entitlements"].update(mutation)
                else:
                    fixture.update(mutation)
                with self.assertRaisesRegex(SigningError, "App Store distribution"):
                    self.check(fixture)

    def test_rejects_certificate_not_in_profile(self):
        with self.assertRaisesRegex(SigningError, "certificate"):
            self.check({**profile(), "DeveloperCertificates": [b"different-certificate"]})

    def test_rejects_wrong_platform_and_unsafe_uuid(self):
        for mutation in ({"Platform": ["OSX"]}, {"UUID": "../../outside"}):
            with self.subTest(mutation=mutation), self.assertRaises(SigningError):
                self.check({**profile(), **mutation})


class ConfigurationTests(unittest.TestCase):
    def test_export_only_does_not_require_upload_credentials(self):
        config = validate_environment(environment(), BUNDLE)
        self.assertFalse(config["upload"])
        self.assertEqual(config["widget"], WIDGET)

    def test_missing_widget_profile_fails_before_archive(self):
        fixture = environment()
        del fixture["IOS_WIDGET_PROFILE_BASE64"]
        with self.assertRaisesRegex(SigningError, "IOS_WIDGET_PROFILE_BASE64"):
            validate_environment(fixture, BUNDLE)

    def test_explicit_build_number_is_required_and_validated(self):
        for build in ("", "0", "-1", "1\nOTHER=2", "1.2.3.4", "10000", "2.100"):
            with self.subTest(build=build), self.assertRaises(SigningError):
                validate_environment({**environment(), "IOS_BUILD_NUMBER": build}, BUNDLE)
        for build in ("196", "9999", "2.10.3"):
            validate_environment({**environment(), "IOS_BUILD_NUMBER": build}, BUNDLE)

    def test_upload_requires_all_api_credentials_before_archive(self):
        fixture = {**environment(), "IOS_UPLOAD": "true"}
        with self.assertRaisesRegex(SigningError, "ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_P8_BASE64"):
            validate_environment(fixture, BUNDLE)

    def test_upload_key_format_validated_without_echoing_values(self):
        fixture = dict(environment(), IOS_UPLOAD="true", ASC_API_KEY_ID="ABC1234567",
                       ASC_API_ISSUER_ID="33333333-3333-3333-3333-333333333333",
                       ASC_API_KEY_P8_BASE64=base64.b64encode(b"-----BEGIN PRIVATE KEY-----\nfixture").decode())
        self.assertTrue(validate_environment(fixture, BUNDLE)["upload"])
        for key, value in (("ASC_API_KEY_ID", "secret-invalid-id"),
                           ("ASC_API_ISSUER_ID", "secret-invalid-issuer"),
                           ("ASC_API_KEY_P8_BASE64", "secret-invalid-key")):
            with self.subTest(key=key), self.assertRaises(SigningError) as caught:
                validate_environment({**fixture, key: value}, BUNDLE)
            self.assertNotIn(value, str(caught.exception))

    def test_refuses_firebase_bundle_mismatch(self):
        with self.assertRaisesRegex(SigningError, "GoogleService-Info"):
            validate_environment(environment(), "com.other.app")

    def test_widget_must_be_distinct_and_under_main_bundle(self):
        for widget in (BUNDLE, "com.other.widgets", BUNDLE + ".*", BUNDLE + ".widget\nINJECT"):
            with self.subTest(widget=widget), self.assertRaises(SigningError):
                validate_environment({**environment(), "IOS_WIDGET_BUNDLE_ID": widget}, BUNDLE)

    def test_invalid_base64_does_not_echo_secret(self):
        fixture = {**environment(), "IOS_PROFILE_BASE64": "DO-NOT-ECHO-THIS"}
        with self.assertRaisesRegex(SigningError, "valid base64") as caught:
            validate_environment(fixture, BUNDLE)
        self.assertNotIn(fixture["IOS_PROFILE_BASE64"], str(caught.exception))

    def test_overlay_preserves_source_spec_and_assigns_each_target_its_profile(self):
        config = validate_environment(environment(), BUNDLE)
        original = copy.deepcopy(config)
        overlay, export = build_configuration(config, APP_PROFILE, WIDGET_PROFILE)
        self.assertEqual(config, original)
        self.assertEqual(overlay["include"], ["project.yml"])
        self.assertNotIn("settings", overlay)
        self.assertEqual(set(overlay["targets"]), {"Streamify", "StreamifyWidgets"})
        for target, bundle, identifier in (("Streamify", BUNDLE, APP_PROFILE),
                                           ("StreamifyWidgets", WIDGET, WIDGET_PROFILE)):
            settings = overlay["targets"][target]["settings"]["base"]
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], bundle)
            self.assertEqual(settings["PROVISIONING_PROFILE_SPECIFIER"], identifier)
            self.assertEqual(settings["CODE_SIGN_STYLE"], "Manual")
        decoded_export = plistlib.loads(plistlib.dumps(export))
        self.assertEqual(decoded_export["provisioningProfiles"], {BUNDLE: APP_PROFILE, WIDGET: WIDGET_PROFILE})
        self.assertEqual(decoded_export["method"], "app-store-connect")

    def test_duplicate_app_and_widget_profile_fails(self):
        with self.assertRaisesRegex(SigningError, "distinct provisioning"):
            build_configuration(validate_environment(environment(), BUNDLE), APP_PROFILE, APP_PROFILE)


class MaterialTests(unittest.TestCase):
    def test_certificate_read_supports_legacy_keychain_p12_exports(self):
        with patch("testflight_signing.run_checked", side_effect=[SigningError("fixture"), b"certificate"]) as run:
            self.assertEqual(read_certificate(Path("fixture.p12")), b"certificate")
            self.assertNotIn("-legacy", run.call_args_list[0].args[0])
            self.assertEqual(run.call_args_list[1].args[0][-1], "-legacy")

    def test_private_write_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "material"
            private_write(path, b"original")
            with self.assertRaises(FileExistsError):
                private_write(path, b"replacement")
            self.assertEqual(path.read_bytes(), b"original")

    def test_identity_requires_matching_valid_distribution_private_key(self):
        fingerprint = "A" * 40
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "certificate-sha1").write_text(fingerprint, encoding="ascii")
            for output in (b"0 valid identities found", ("1) " + "B" * 40 + ' "Apple Distribution: Fixture"').encode(),
                           ("1) " + fingerprint + ' "Apple Development: Fixture"').encode()):
                with patch("testflight_signing.run_checked", return_value=output), self.assertRaises(SigningError):
                    verify_identity(folder)
            with patch("testflight_signing.run_checked", return_value=(
                    "1) " + fingerprint + ' "Apple Distribution: Fixture"').encode()):
                verify_identity(folder)

    def test_cleanup_removes_only_owned_material(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ios, signing, profiles = root / "ios", root / "signing", root / "profiles"
            ios.mkdir()
            signing.mkdir()
            profiles.mkdir()
            unrelated = profiles / "unrelated.mobileprovision"
            unrelated.write_bytes(b"retain")
            installed = profiles / (APP_PROFILE + ".mobileprovision")
            installed.write_bytes(b"fixture")
            (signing / "owned-by-testflight").write_bytes(b"true")
            (signing / "owns-overlay").write_bytes(b"true")
            (ios / ".testflight-project.json").write_bytes(b"{}")
            (signing / "installed-profiles.json").write_text(json.dumps([str(installed)]), encoding="utf-8")
            with patch("testflight_signing.profile_directories", return_value=[profiles]):
                cleanup(ios, signing)
            self.assertFalse(signing.exists())
            self.assertFalse(installed.exists())
            self.assertFalse((ios / ".testflight-project.json").exists())
            self.assertEqual(unrelated.read_bytes(), b"retain")

    def test_cleanup_ignores_preexisting_unowned_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            marker = folder / "unrelated"
            marker.write_bytes(b"retain")
            cleanup(folder, folder)
            self.assertEqual(marker.read_bytes(), b"retain")


if __name__ == "__main__":
    unittest.main(verbosity=2)
