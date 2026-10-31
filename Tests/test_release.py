import os
from pathlib import Path
import plistlib
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'Scripts'))
from ci_version import resolve
from set_version import normalize


class ReleaseInputs(unittest.TestCase):
    def test_build_defaults_to_template_version(self):
        self.assertEqual(resolve(False, '', '0.7.0'), '0.7.0')

    def test_publish_requires_explicit_version(self):
        with self.assertRaises(ValueError):
            resolve(True, '  ', '0.7.0')

    def test_version_is_normalized(self):
        self.assertEqual(resolve(True, 'v1.2.3', '0.7.0'), '1.2.3')

    def test_invalid_versions_and_shell_payloads_are_rejected(self):
        for version in ['1.0', '01.0.0', '1.0.0; echo secret', '$(id)', '../1.0.0', '1.0.0\n2']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                normalize(version)

    def test_app_identity(self):
        info = plistlib.loads((Path(__file__).resolve().parents[1]/'App/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], 'com.shengjian.app')
        self.assertEqual(info['CFBundleExecutable'], 'Shengjian')


if __name__ == '__main__':
    unittest.main()
