"""Generate the public updater manifest beside a signed APK."""
import hashlib
import json
import pathlib
import sys

apk = pathlib.Path(sys.argv[1])
code, name, repo = int(sys.argv[2]), sys.argv[3], sys.argv[4]
assert 0 < code <= 2100000000
manifest = dict(versionCode=code, versionName=name,
    url=f"https://github.com/{repo}/releases/download/android-v{code}/{apk.name}",
    sha256=hashlib.sha256(apk.read_bytes()).hexdigest(), size=apk.stat().st_size,
    notes="Latest Android fixes and improvements.")
apk.with_name("update.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
