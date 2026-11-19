"""Prepare target-specific TestFlight signing without modifying the source project.

Only prepare/verify-identity need macOS security and OpenSSL. Errors never include
credential values or subprocess output. Portable fixtures cover the pure helpers.
"""
import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import uuid


class SigningError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise SigningError(message)


def decode_secret(env, name):
    try:
        value = base64.b64decode(env[name], validate=True)
    except (binascii.Error, ValueError):
        raise SigningError(f"{name} must contain valid base64.") from None
    require(bool(value), f"{name} must not be empty.")
    return value


def validate_environment(env, firebase_bundle):
    upload = env.get("IOS_UPLOAD", "false").lower() == "true"
    required = ["IOS_TEAM_ID", "IOS_BUNDLE_ID", "IOS_BUILD_NUMBER", "IOS_CERTIFICATE_P12_BASE64",
                "IOS_CERTIFICATE_PASSWORD", "IOS_PROFILE_BASE64", "IOS_WIDGET_PROFILE_BASE64"]
    if upload:
        required += ["ASC_API_KEY_ID", "ASC_API_ISSUER_ID", "ASC_API_KEY_P8_BASE64"]
    missing = [key for key in required if not env.get(key)]
    require(not missing, "Missing signing configuration: " + ", ".join(missing) + ". See ios/README.md.")
    team, bundle = env["IOS_TEAM_ID"], env["IOS_BUNDLE_ID"]
    widget = env.get("IOS_WIDGET_BUNDLE_ID") or bundle + ".widgets"
    require(bool(re.fullmatch(r"[A-Z0-9]{10}", team)), "IOS_TEAM_ID must be a 10-character Apple Team ID.")
    require(bool(re.fullmatch(r"[1-9][0-9]{0,3}(?:\.[0-9]{1,2}){0,2}", env["IOS_BUILD_NUMBER"])),
            "build_number must be a CFBundleVersion: a positive integer up to 9999, optionally followed by two components up to 99.")
    for value in (bundle, widget):
        require(bool(re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", value)),
                "App and widget bundle identifiers must be explicit reverse-DNS identifiers.")
    require(widget.startswith(bundle + "."), "Widget bundle identifier must extend the main app identifier.")
    require(bundle == firebase_bundle,
            "IOS_BUNDLE_ID must match the bundled GoogleService-Info.plist to preserve account sign-in.")
    material = {key: decode_secret(env, key) for key in
                ("IOS_CERTIFICATE_P12_BASE64", "IOS_PROFILE_BASE64", "IOS_WIDGET_PROFILE_BASE64")}
    if upload:
        require(bool(re.fullmatch(r"[A-Za-z0-9]{10}", env["ASC_API_KEY_ID"])), "Invalid ASC_API_KEY_ID.")
        try:
            uuid.UUID(env["ASC_API_ISSUER_ID"])
        except ValueError:
            raise SigningError("ASC_API_ISSUER_ID must be a team API key issuer UUID.") from None
        material["ASC_API_KEY_P8_BASE64"] = decode_secret(env, "ASC_API_KEY_P8_BASE64")
        require(material["ASC_API_KEY_P8_BASE64"].startswith(b"-----BEGIN PRIVATE KEY-----"),
                "ASC_API_KEY_P8_BASE64 must contain an App Store Connect .p8 private key.")
    return dict(team=team, bundle=bundle, widget=widget, upload=upload, material=material)


def validate_profile(profile, team, bundle, certificate, label, now=None):
    require(isinstance(profile, dict), f"{label}: invalid provisioning profile.")
    entitlements = profile.get("Entitlements", {})
    require(isinstance(entitlements, dict), f"{label}: invalid entitlements.")
    require(profile.get("TeamIdentifier") == [team] and
            entitlements.get("com.apple.developer.team-identifier") == team,
            f"{label}: provisioning team does not match IOS_TEAM_ID.")
    # Older accounts may have an App ID prefix different from their Team ID.
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    app_identifier = entitlements.get("application-identifier")
    require(isinstance(prefixes, list) and any(
        isinstance(prefix, str) and app_identifier == prefix + "." + bundle for prefix in prefixes),
        f"{label}: profile must match the target's exact bundle identifier.")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, dt.datetime), f"{label}: profile expiration is missing.")
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=dt.timezone.utc)
    require(expiry > (now or dt.datetime.now(dt.timezone.utc)), f"{label}: provisioning profile has expired.")
    require("ProvisionedDevices" not in profile and not profile.get("ProvisionsAllDevices") and
            entitlements.get("get-task-allow") is False,
            f"{label}: use an App Store distribution profile, not development, ad hoc or enterprise.")
    require("iOS" in profile.get("Platform", []), f"{label}: profile must support iOS.")
    require(certificate in profile.get("DeveloperCertificates", []),
            f"{label}: profile does not include the supplied distribution certificate.")
    profile_uuid = profile.get("UUID", "")
    require(isinstance(profile_uuid, str) and bool(re.fullmatch(
        r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", profile_uuid)),
        f"{label}: profile UUID is invalid.")
    return profile_uuid


def build_configuration(config, app_profile, widget_profile):
    require(app_profile != widget_profile, "App and widget must use distinct provisioning profiles.")
    targets = {}
    for target, bundle, profile in (("Streamify", config["bundle"], app_profile),
                                    ("StreamifyWidgets", config["widget"], widget_profile)):
        targets[target] = {"settings": {"base": {
            "PRODUCT_BUNDLE_IDENTIFIER": bundle,
            "DEVELOPMENT_TEAM": config["team"],
            "CODE_SIGN_STYLE": "Manual",
            "CODE_SIGN_IDENTITY": "Apple Distribution",
            "PROVISIONING_PROFILE_SPECIFIER": profile,
        }}}
    overlay = {"include": ["project.yml"], "targets": targets}
    export = dict(method="app-store-connect", destination="export", signingStyle="manual",
                  teamID=config["team"], signingCertificate="Apple Distribution",
                  provisioningProfiles={config["bundle"]: app_profile, config["widget"]: widget_profile},
                  manageAppVersionAndBuildNumber=False, uploadSymbols=True)
    return overlay, export


def run_checked(command, message, data=None):
    try:
        result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except OSError:
        raise SigningError(message) from None
    require(result.returncode == 0, message)
    return result.stdout


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def read_certificate(p12):
    command = ["openssl", "pkcs12", "-in", str(p12), "-clcerts", "-nokeys",
               "-passin", "env:IOS_CERTIFICATE_PASSWORD"]
    message = "Unable to read distribution certificate from the P12; check its password and format."
    try:
        return run_checked(command, message)
    except SigningError:
        # Keychain exports can use RC2, which OpenSSL 3 moves to its legacy provider.
        # Older OpenSSL/LibreSSL reads these on the first attempt without this flag.
        return run_checked(command + ["-legacy"], message)


def profile_directories():
    # Xcode 16+ uses UserData; retain the older location for runner compatibility.
    return [Path.home() / "Library/MobileDevice/Provisioning Profiles",
            Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]


def prepare(ios, folder):
    firebase = plistlib.loads((ios / "Streamify/Resources/GoogleService-Info.plist").read_bytes())
    config = validate_environment(os.environ, firebase.get("BUNDLE_ID"))
    require(not folder.exists(), "TestFlight temporary signing directory already exists.")
    require(not (ios / ".testflight-project.json").exists(), "Temporary TestFlight project already exists.")
    folder.mkdir(mode=0o700, parents=True)
    private_write(folder / "owned-by-testflight", b"true")
    private_write(folder / "signing.p12", config["material"]["IOS_CERTIFICATE_P12_BASE64"])
    certificate_pem = read_certificate(folder / "signing.p12")
    certificate = run_checked(["openssl", "x509", "-outform", "DER"],
                              "P12 must contain a signing certificate.", certificate_pem)
    run_checked(["openssl", "x509", "-checkend", "0", "-noout"],
                "Distribution certificate has expired.", certificate_pem)
    profile_ids = []
    for label, bundle, secret, filename in (
        ("App", config["bundle"], "IOS_PROFILE_BASE64", "app.mobileprovision"),
        ("Widget", config["widget"], "IOS_WIDGET_PROFILE_BASE64", "widget.mobileprovision"),
    ):
        source = folder / filename
        private_write(source, config["material"][secret])
        decoded = run_checked(["security", "cms", "-D", "-i", str(source)],
                              f"{label}: cannot decode provisioning profile.")
        try:
            profile = plistlib.loads(decoded)
        except Exception:
            raise SigningError(f"{label}: invalid provisioning profile data.") from None
        profile_ids.append(validate_profile(profile, config["team"], bundle, certificate, label))
    overlay, export = build_configuration(config, *profile_ids)
    if config["upload"]:
        key = config["material"]["ASC_API_KEY_P8_BASE64"]
        # Apple's .p8 is an EC key. `ec -check` works with both LibreSSL and OpenSSL;
        # the generic `pkey -check` flag is unavailable in macOS LibreSSL versions.
        run_checked(["openssl", "ec", "-check", "-noout"], "App Store Connect EC private key is invalid.", key)
        private_write(folder / "private_keys" / ("AuthKey_" + os.environ["ASC_API_KEY_ID"] + ".p8"), key)
    private_write(folder / "ExportOptions.plist", plistlib.dumps(export))
    private_write(folder / "certificate-sha1", hashlib.sha1(certificate).hexdigest().upper().encode("ascii"))
    installed = []
    manifest = folder / "installed-profiles.json"
    private_write(manifest, b"[]")
    for filename, profile_id in zip(("app.mobileprovision", "widget.mobileprovision"), profile_ids):
        for destination in profile_directories():
            target = destination / (profile_id + ".mobileprovision")
            private_write(target, (folder / filename).read_bytes())
            installed.append(str(target))
            manifest.write_text(json.dumps(installed), encoding="utf-8")
    private_write(ios / ".testflight-project.json", json.dumps(overlay, indent=2).encode("utf-8"))
    private_write(folder / "owns-overlay", b"true")
    print("Validated separate app/widget profiles and prepared target-specific signing.")


def verify_identity(folder):
    expected = (folder / "certificate-sha1").read_text(encoding="ascii")
    identities = run_checked(["security", "find-identity", "-v", "-p", "codesigning",
                              str(folder / "signing.keychain-db")],
                             "Cannot inspect imported signing identity.").decode("utf-8", errors="replace")
    require(any(re.search(r"\b" + re.escape(expected) + r'\s+"Apple Distribution:', line)
                for line in identities.splitlines()),
            "Imported P12 must contain a valid Apple Distribution identity and its private key matching both profiles.")
    print("Verified the distribution identity and matching private key.")


def cleanup(ios, folder):
    if not folder.is_dir() or folder.is_symlink() or not (folder / "owned-by-testflight").is_file():
        return
    manifest = folder / "installed-profiles.json"
    if manifest.is_file():
        roots = set(profile_directories())
        for value in json.loads(manifest.read_text(encoding="utf-8")):
            path = Path(value)
            require(path.parent in roots and bool(re.fullmatch(
                r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}\.mobileprovision", path.name)),
                "Unexpected installed provisioning profile path; cleanup stopped.")
            path.unlink(missing_ok=True)
    if (folder / "owns-overlay").is_file():
        (ios / ".testflight-project.json").unlink(missing_ok=True)
    shutil.rmtree(folder)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "verify-identity", "cleanup"))
    args = parser.parse_args()
    ios = Path(__file__).resolve().parents[1]
    require(bool(os.environ.get("RUNNER_TEMP")), "RUNNER_TEMP is required; run signing in the GitHub macOS workflow.")
    folder = Path(os.environ["RUNNER_TEMP"]).resolve() / "streamify-testflight"
    if args.command == "prepare":
        prepare(ios, folder)
    elif args.command == "verify-identity":
        verify_identity(folder)
    else:
        cleanup(ios, folder)


if __name__ == "__main__":
    try:
        main()
    except SigningError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
