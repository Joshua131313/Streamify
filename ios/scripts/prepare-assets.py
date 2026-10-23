"""Copy existing Android artwork into iOS asset catalogs; requires Pillow.

All output is committed. This utility is only needed when the shared assets change.
"""
import json
from pathlib import Path
import shutil
import sys

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parent
sys.path.insert(0, str(IOS / ".tools"))
from PIL import Image

resources = IOS / "Streamify/Resources"
assets = resources / "Assets.xcassets"
assets.mkdir(parents=True, exist_ok=True)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


info = {"author": "xcode", "version": 1}
write_json(assets / "Contents.json", {"info": info})


def imageset(name, source):
    target = assets / (name + ".imageset")
    target.mkdir(exist_ok=True)
    shutil.copy2(source, target / source.name)
    write_json(target / "Contents.json", {"images": [{"idiom": "universal", "filename": source.name}], "info": info})


android = ROOT / "android/app/src/main"
drawables = android / "res/drawable-nodpi"
imageset("streamify-logo", drawables / "streamify_logo.png")
imageset("espn-logo", drawables / "espn_logo.png")
for league in ["nfl", "nba", "wnba", "nhl", "mlb"]:
    imageset("league-" + league, drawables / ("league_" + league + ".png"))
for source in (android / "assets/collections").glob("*.jpg"):
    imageset("collection-" + source.stem, source)
for filename in ["collections.json", "media-servers.json"]:
    shutil.copy2(android / "assets" / filename, resources / filename)

icon = assets / "AppIcon.appiconset"
icon.mkdir(exist_ok=True)
canvas = Image.new("RGB", (1024, 1024), (11, 13, 16))
logo = Image.open(drawables / "streamify_logo.png").convert("RGBA")
logo.thumbnail((700, 700), Image.Resampling.LANCZOS)
canvas.paste(logo, ((1024 - logo.width) // 2, (1024 - logo.height) // 2), logo)
canvas.save(icon / "AppIcon.png")
write_json(icon / "Contents.json", {"images": [{"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon.png"}], "info": info})
color = assets / "LaunchBackground.colorset"
color.mkdir(exist_ok=True)
write_json(color / "Contents.json", {"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.043", "green": "0.051", "blue": "0.063", "alpha": "1.000"}}}], "info": info})
print("Prepared original brand artwork, five leagues, 17 collections, app icon, and catalog configuration.")
