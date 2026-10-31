"""Verify changed releases satisfy the old certificate-bound code identity.
Does not modify the installed app, TCC, or user permissions.
"""
from pathlib import Path
import hashlib
import os
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
signing_dir = Path(os.environ.get('SHENGJIAN_SIGNING_DIR', str(Path.home() / 'Library/Application Support/Shengjian/Signing')))
identity = (signing_dir / 'certificate.sha1').read_text().strip()

def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    return result.stdout + result.stderr

original = root / 'build/声笺.app'
requirement = run('codesign', '-d', '-r-', str(original)).split('designated => ', 1)[1].splitlines()[0].strip()
assert 'certificate leaf' in requirement and 'cdhash' not in requirement
assert identity.lower() in requirement.lower()
with tempfile.TemporaryDirectory(prefix='rimevoice-upgrade-check-') as directory:
    updated = Path(directory) / '声笺.app'
    shutil.copytree(original, updated)
    info = updated / 'Contents/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data['CFBundleVersion'] += '-upgrade-test'
    info.write_bytes(plistlib.dumps(data))
    run('codesign', '--force', '--sign', identity, '--requirements', '=designated => ' + requirement, str(updated))
    run('codesign', '--verify', '--strict', '-R', '=' + requirement, str(updated))
    updated_requirement = run('codesign', '-d', '-r-', str(updated)).split('designated => ', 1)[1].splitlines()[0].strip()
    assert requirement == updated_requirement
    old_bytes = (original / 'Contents/MacOS/Shengjian').read_bytes()
    new_bytes = (updated / 'Contents/MacOS/Shengjian').read_bytes()
    assert hashlib.sha256(old_bytes).digest() != hashlib.sha256(new_bytes).digest()
    print('PASS: Changed, re-signed release satisfies the original identity; DR unchanged.')
    print('NOTE: Runtime permission retention still requires a real authorized upgrade test.')
