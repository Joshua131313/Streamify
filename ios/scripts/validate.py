"""Validate portable iOS source/resources. This does not replace an Xcode build."""
import argparse
import json
from pathlib import Path
import plistlib
import struct
import sys

ios = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--syntax", action="store_true", help="Also parse Swift syntax using locally installed tree-sitter packages")
args = parser.parse_args()
errors = []
resources = ios / "Streamify/Resources"
widget_resources = ios / "StreamifyWidgets"
resource_json = sorted(resources.rglob("*.json")) + sorted(widget_resources.rglob("*.json"))
for path in resource_json:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if path.name == "Contents.json":
            for item in value.get("images", []):
                if "filename" in item and not (path.parent / item["filename"]).is_file():
                    errors.append(f"Missing asset: {path.parent / item['filename']}")
    except Exception as exc:
        errors.append(f"{path}: {exc}")
for path in [resources / "Info.plist", resources / "PrivacyInfo.xcprivacy", widget_resources / "Info.plist"]:
    try:
        with path.open("rb") as source:
            plistlib.load(source)
    except Exception as exc:
        errors.append(f"{path}: {exc}")
try:
    firebase = plistlib.loads((resources / "GoogleService-Info.plist").read_bytes())
    if firebase.get("BUNDLE_ID") != "com.streamify.app" or firebase.get("PROJECT_ID") != "debugging-98550":
        errors.append("Guest chat Firebase configuration must match the existing Streamify app and project.")
    if not firebase.get("API_KEY") or not firebase.get("GOOGLE_APP_ID"):
        errors.append("Guest chat Firebase configuration is incomplete.")
except Exception as exc:
    errors.append(f"Guest chat Firebase configuration: {exc}")
collections = json.loads((resources / "collections.json").read_text())
servers = json.loads((resources / "media-servers.json").read_text())
if len(collections) != 17 or len(servers) != 15:
    errors.append("Expected the Android catalog's 17 collections and 15 video providers.")
for item in collections:
    asset = resources / "Assets.xcassets" / ("collection-" + Path(item["backdrop"]).stem + ".imageset")
    if not asset.is_dir():
        errors.append(f"Missing collection asset: {asset}")
icon = resources / "Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if icon.is_file():
    header = icon.read_bytes()[:26]
    if struct.unpack(">II", header[16:24]) != (1024, 1024) or header[25] not in (0, 2):
        errors.append("App icon must be an opaque 1024x1024 PNG.")
else:
    errors.append("App icon missing.")
swift_files = sorted((ios / "Streamify").rglob("*.swift")) + sorted((ios / "StreamifyWidgets").rglob("*.swift")) + sorted((ios / "StreamifyTests").rglob("*.swift")) + sorted((ios / "StreamifyUITests").rglob("*.swift"))
for path in swift_files:
    if b"\x00" in path.read_bytes():
        errors.append(f"{path.relative_to(ios)}: source contains NUL bytes")
if args.syntax:
    sys.path.insert(0, str(ios / ".tools"))
    from tree_sitter import Language, Parser
    import tree_sitter_swift
    swift_parser = Parser(Language(tree_sitter_swift.language()))
    for path in swift_files:
        tree = swift_parser.parse(path.read_bytes())
        nodes = [tree.root_node]
        while nodes:
            node = nodes.pop()
            if node.type == "ERROR" or node.is_missing:
                errors.append(f"{path.relative_to(ios)}:{node.start_point.row + 1}:{node.start_point.column + 1}: syntax {node.type}")
            nodes.extend(reversed(node.children))
if errors:
    print("\n".join(errors))
    raise SystemExit(1)
print(f"Validated resources, property lists, {len(collections)} collections, {len(servers)} providers, and {len(swift_files)} Swift files" + (" (syntax parsed)." if args.syntax else "."))
print("Swift type checking, XCTest, and rendering still require Xcode on macOS.")
