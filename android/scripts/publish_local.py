"""Publish a locally built, signed tester APK. Authentication stays in Git credential manager.
Usage: python android/scripts/publish_local.py path/to/Streamify.apk VERSION_CODE VERSION_NAME
"""
import json, pathlib, subprocess, sys, urllib.request
apk = pathlib.Path(sys.argv[1]).resolve()
code, name = int(sys.argv[2]), sys.argv[3]
repo = "Joshua131313/streamify"
subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("release_metadata.py")), str(apk), str(code), name, repo], check=True)
result = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n", capture_output=True, text=True, check=True)
credential = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
headers = {"Authorization": "Bearer " + credential["password"], "Accept": "application/vnd.github+json", "User-Agent": "Streamify-local-release"}
base = "https://api.github.com/repos/" + repo
sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
def request(url, data, method="POST", content_type="application/json"):
    req = urllib.request.Request(url, data=data, method=method, headers=dict(headers, **{"Content-Type": content_type}))
    with urllib.request.urlopen(req, timeout=180) as response: return json.load(response)
release = request(base + "/releases", json.dumps(dict(tag_name=f"android-v{code}", target_commitish=sha, name=f"Streamify Android {name}", draft=True, body="Latest Android fixes and UI improvements. Update from Settings → App updates in Streamify.")).encode())
for path, content_type in [(apk, "application/vnd.android.package-archive"), (apk.with_name("update.json"), "application/json")]:
    upload = release["upload_url"].split("{")[0] + "?name=" + path.name
    request(upload, path.read_bytes(), content_type=content_type)
release = request(base + "/releases/" + str(release["id"]), b'{"draft":false}', method="PATCH")
print(release["html_url"])
