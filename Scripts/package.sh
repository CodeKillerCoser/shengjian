#!/bin/bash
set -euo pipefail
: "${APP_VERSION:?Missing APP_VERSION}"
mkdir -p dist
archive="Shengjian-${APP_VERSION}-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent build/声笺.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > SHA256SUMS)
python3 - <<'PY'
import json, os, plistlib, subprocess
from pathlib import Path
app = Path('build/声笺.app')
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
manifest = {
    'name': '声笺', 'bundle_id': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'configuration': 'Release', 'commit': os.environ.get('GITHUB_SHA', ''),
    'architectures': subprocess.check_output(['lipo', '-archs', str(app/'Contents/MacOS/Shengjian')], text=True).split(),
}
assert set(manifest['architectures']) == {'arm64'}
Path('dist/build-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
PY
