#!/usr/bin/env python3
import os
import plistlib
from pathlib import Path
from set_version import normalize


def resolve(release, entered, fallback):
    if release and not entered.strip():
        raise ValueError('勾选发布时必须填写版本号，例如 1.0.0')
    return normalize(entered.strip() or fallback)


if __name__ == '__main__':
    release = os.environ.get('PUBLISH_RELEASE', 'false') == 'true'
    if release and os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise SystemExit('发布只能从 main 分支运行')
    info = plistlib.loads(Path('App/Info.plist').read_bytes())
    version = resolve(release, os.environ.get('REQUESTED_VERSION', ''), info['CFBundleShortVersionString'])
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'version={version}\ntag=v{version}\n')
    print('Release version:', version)
