#!/usr/bin/env python3
import os
import plistlib
import re
import sys
from pathlib import Path


def normalize(value):
    version = value.removeprefix('v')
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('版本号须为 X.Y.Z，例如 1.0.0')
    return version


def main():
    path = Path(sys.argv[1])
    info = plistlib.loads(path.read_bytes())
    version = normalize(os.environ.get('APP_VERSION') or info['CFBundleShortVersionString'])
    build = os.environ.get('BUILD_NUMBER') or info['CFBundleVersion']
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', build):
        raise ValueError('BUILD_NUMBER 必须为数字版本号')
    info['CFBundleShortVersionString'] = version
    info['CFBundleVersion'] = build
    path.write_bytes(plistlib.dumps(info))


if __name__ == '__main__':
    main()
