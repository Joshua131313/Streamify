"""Prepare a SideStore/AltStore Classic feed from a verified unsigned device IPA.

This script is offline: it neither publishes a release nor checks whether its URL
exists. Run it only after the intended IPA has passed build and device checks.
Schema: https://faq.altstore.io/developers/make-a-source
"""
import argparse
from datetime import date
import json
from pathlib import Path
import plistlib
import re
import sys
import zipfile


IOS = Path(__file__).resolve().parents[1]
REPOSITORY = "Joshua131313/Streamify"
BUNDLE_ID = "com.streamify.app"
RAW_BASE = f"https://raw.githubusercontent.com/{REPOSITORY}/refs/heads/codex/native-ios"
SOURCE_URL = f"{RAW_BASE}/ios/sideload-source.json"
ICON_URL = f"{RAW_BASE}/ios/Streamify/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
VERSION_PATTERN = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
NUMBER_PATTERN = r"[0-9]+(?:\.[0-9]+){0,2}"


def read_ipa(path, expected_version):
    """Read the main bundle without extracting or executing any archive content."""
    path = Path(path)
    if path.suffix.lower() != ".ipa" or not path.is_file():
        raise ValueError("Choose an existing unsigned .ipa file.")
    size = path.stat().st_size
    if not 0 < size <= 512 * 1024 * 1024:
        raise ValueError("IPA archive size must be between 1 byte and 512 MiB.")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        main = [entry for entry in entries if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", entry.filename)]
        if len(main) != 1 or main[0].file_size > 1024 * 1024:
            raise ValueError("Expected exactly one main app with a bounded Info.plist.")
        if any("/_CodeSignature/" in entry.filename or entry.filename.endswith("/embedded.mobileprovision") for entry in entries):
            raise ValueError("Use the unsigned CI IPA, not a personally signed or provisioned app.")
        if any("/PlugIns/" in entry.filename or entry.filename.endswith(".appex/Info.plist") for entry in entries):
            raise ValueError("App extensions require a separate permissions review before feed generation.")
        info = plistlib.loads(archive.read(main[0]))
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError(f"IPA bundle identifier must be exactly {BUNDLE_ID}.")
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    minimum = info.get("MinimumOSVersion")
    if not isinstance(version, str) or len(version) > 80 or not re.fullmatch(VERSION_PATTERN, version):
        raise ValueError("IPA marketing version must be a stable numeric major.minor.patch value.")
    if version != expected_version:
        raise ValueError(f"IPA version {version!r} does not match expected version {expected_version!r}.")
    if not isinstance(build, str) or len(build) > 80 or not re.fullmatch(NUMBER_PATTERN, build):
        raise ValueError("IPA build number is missing or invalid.")
    if not isinstance(minimum, str) or len(minimum) > 20 or not re.fullmatch(NUMBER_PATTERN, minimum):
        raise ValueError("IPA MinimumOSVersion is missing or invalid.")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Expected a physical-device iPhoneOS IPA, not a simulator build.")
    privacy = {}
    for key, value in info.items():
        if isinstance(key, str) and key.startswith("NS") and "UsageDescription" in key:
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"Invalid privacy description for {key}.")
            privacy[key] = value
    return {"version": version, "build": build, "minimum": minimum, "size": size, "privacy": privacy}


def make_source(metadata, release_date, notes):
    """Use Classic IPA fields; no notarized marketplace/PAL fields are needed."""
    version = metadata["version"]
    asset_name = f"Streamify-{version}-unsigned.ipa"
    release_url = f"https://github.com/{REPOSITORY}/releases/download/ios-v{version}/{asset_name}"
    return {
        "name": "Streamify iOS",
        "identifier": "com.streamify.ios.source",
        "sourceURL": SOURCE_URL,
        "apps": [{
            "name": "Streamify",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "Joshua131313",
            "localizedDescription": "Native iPhone and iPad interface for Streamify movies, shows, anime and live sports.",
            "iconURL": ICON_URL,
            "versions": [{
                "version": version,
                "buildVersion": metadata["build"],
                "date": release_date,
                "localizedDescription": notes,
                "downloadURL": release_url,
                "size": metadata["size"],
                "minOSVersion": metadata["minimum"],
            }],
            "appPermissions": {"entitlements": [], "privacy": metadata["privacy"]},
        }],
        "news": [],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path, help="New verified unsigned iPhone IPA")
    parser.add_argument("--expected-version", required=True, help="Expected major.minor.patch; must match the IPA")
    parser.add_argument("--date", required=True, help="Release date as YYYY-MM-DD")
    parser.add_argument("--notes", default="Native iOS interface improvements.", help="Plain release notes, at most 2000 characters")
    parser.add_argument("--output", type=Path, default=IOS / "sideload-source.json")
    args = parser.parse_args()
    try:
        if date.fromisoformat(args.date).isoformat() != args.date:
            raise ValueError("Release date must use YYYY-MM-DD.")
        if not re.fullmatch(VERSION_PATTERN, args.expected_version):
            raise ValueError("Expected version must use major.minor.patch.")
        if not args.notes.strip() or len(args.notes) > 2000 or "\0" in args.notes:
            raise ValueError("Provide 1–2000 characters of plain release notes.")
        metadata = read_ipa(args.ipa, args.expected_version)
        output = args.output.resolve()
        if output == args.ipa.resolve() or output.suffix.lower() != ".json":
            raise ValueError("Choose a .json output distinct from the IPA.")
        source = make_source(metadata, args.date, args.notes.strip())
        output.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Cannot prepare source: {error}\n")
    print(f"Prepared {output}")
    print(f"Version {metadata['version']}, build {metadata['build']}, iOS {metadata['minimum']}+, IPA archive {metadata['size']} bytes")
    print(f"Required public release asset: {source['apps'][0]['versions'][0]['downloadURL']}")
    print("Nothing was published. Verify the release asset and icon, then publish this source separately.")


if __name__ == "__main__":
    sys.exit(main())
