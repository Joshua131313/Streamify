"""Bundle ESPN's team marks for offline ActivityKit rendering (no widget network)."""
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import json
import urllib.request
from PIL import Image

ios = Path(__file__).resolve().parents[1]
catalog = ios / 'StreamifyWidgets/Resources/Tracking.xcassets'
catalog.mkdir(parents=True, exist_ok=True)
info = {'author': 'xcode', 'version': 1}
(catalog / 'Contents.json').write_text(json.dumps({'info': info}))

def read(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'Streamify/1.1', 'Accept': 'application/json,image/png'})
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read()

def save(name, data):
    folder = catalog / (name + '.imageset')
    folder.mkdir(exist_ok=True)
    image = Image.open(BytesIO(data)).convert('RGBA')
    image.thumbnail((120, 120), Image.Resampling.LANCZOS)
    image.save(folder / 'logo.png', optimize=True)
    (folder / 'Contents.json').write_text(json.dumps({'info': info, 'images': [{'idiom': 'universal', 'filename': 'logo.png', 'scale': '3x'}]}))

jobs = []
for league, sport in [('nba','basketball'),('wnba','basketball'),('nfl','football'),('college-football','football'),('nhl','hockey'),('mlb','baseball')]:
    raw = json.loads(read(f'https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams?limit=1000'))
    teams = raw.get('sports', [{}])[0].get('leagues', [{}])[0].get('teams', [])
    for entry in teams:
        team = entry.get('team', {})
        logos = team.get('logos', [])
        if str(team.get('id','')).isdigit() and logos:
            jobs.append((f"team-{league}-{team['id']}", logos[0]['href']))
    league_assets = ios / f'Streamify/Resources/Assets.xcassets/league-{league}.imageset'
    image = next(league_assets.glob('*.png'), None)
    if image: save(f'league-{league}', image.read_bytes())
    print(f'{league}: {len(teams)} teams', flush=True)

def download(job):
    name, url = job
    if (catalog / (name + '.imageset') / 'logo.png').exists(): return None
    try:
        if not url.startswith('https://a.espncdn.com/'): raise ValueError('Unexpected logo host')
        save(name, read(url))
    except Exception as error: return f'{name}: {error}'

with ThreadPoolExecutor(max_workers=8) as pool:
    failures = [error for error in pool.map(download, jobs) if error]
print(f'Prepared {len(jobs) - len(failures)} team marks; {len(failures)} unavailable.')
for error in failures: print(error)
if failures: raise SystemExit(1)
