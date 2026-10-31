#!/usr/bin/env python3
"""Upload only the selected signing identity to GitHub Actions encrypted Secrets.
No private key, P12, or password is added to the repository or printed.
"""
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    repo = sys.argv[1] if len(sys.argv) > 1 else 'CodeKillerCoser/shengjian'
    user = json.loads(subprocess.check_output(['gh', 'api', 'user']))['login']
    if user.lower() != repo.split('/')[0].lower():
        raise SystemExit('GitHub 登录账号与仓库所有者不匹配')
    # Check repository access before requesting access to the local private key.
    run('gh', 'api', f'repos/{repo}/actions/secrets/public-key', '--silent')
    fingerprint = (Path.home()/'.config/shengjian/signing/certificate.sha1').read_text().strip()
    run('gh', 'secret', 'set', 'SHENGJIAN_EXPECTED_SIGNING_IDENTITY', '--repo', repo, input=fingerprint.encode())
    with tempfile.TemporaryDirectory(prefix='shengjian-signing-') as temporary:
        path = Path(temporary)
        os.chmod(path, 0o700)
        password = secrets.token_urlsafe(40)
        password_file = path/'password'
        password_file.write_text(password)
        password_file.chmod(0o600)
        exporter = path/'exporter'
        run('swiftc', str(ROOT/'Scripts/ExportSigningIdentity.swift'), '-o', str(exporter), '-framework', 'Security')
        p12 = path/'identity.p12'
        run(str(exporter), fingerprint, str(password_file), str(p12))
        run('gh', 'secret', 'set', 'SIGNING_CERTIFICATE_P12', '--repo', repo,
            input=base64.b64encode(p12.read_bytes()))
        run('gh', 'secret', 'set', 'SIGNING_CERTIFICATE_PASSWORD', '--repo', repo,
            input=password.encode())
    print('Configured signing Secrets for', repo)


if __name__ == '__main__':
    main()
