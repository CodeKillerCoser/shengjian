import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


BOOTSTRAP = Path(__file__).resolve().parents[1] / 'App/BreezeBootstrap'
REVISION = 'f1818ec44da33302701718e5fb15267ce1cf5e4f'

# Fake only network/package commands; execute the real installer, archive extraction and shell traps.
TOOL = '''#!{python}
import json, os, pathlib, sys, tarfile
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['BREEZE_TEST_LOG'], 'a') as log:
    log.write(json.dumps([name, args]) + '\\n')
if name == 'curl':
    sys.exit(0 if os.environ.get('BREEZE_TEST_ACTIVE') else 1)
if name == 'git':
    if args[0] == 'clone':
        pathlib.Path(args[-1]).mkdir()
    else:
        assert args[2:4] == ['archive', '{revision}']
        with tarfile.open(fileobj=sys.stdout.buffer, mode='w|') as archive:
            for item in args[4:]:
                archive.add(pathlib.Path(os.environ['BREEZE_TEST_FIXTURE']) / item, arcname=item)
elif name == 'uv':
    if args[0] == 'venv':
        binary = pathlib.Path('.venv/bin/hf')
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text(pathlib.Path(sys.argv[0]).read_text())
        binary.chmod(0o755)
    else:
        assert args[:2] == ['pip', 'install']
        text = pathlib.Path(args[args.index('-r')+1]).read_text()
        assert 'pytest' not in text and 'ruff' not in text and 'numpy>=2.0' in text
        if os.environ.get('BREEZE_TEST_FAIL'):
            sys.exit(12)
elif name == 'hf':
    assert args == ['download', 'mlx-community/Breeze-TTS-2-mlx', '--revision',
                    '3c8829fb7fd335818f085cd2ef49b4100c0e46c8']
'''


class BreezeBootstrap(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='shengjian-bootstrap-')
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.root = self.base / 'Application Support/Shengjian/Engines/Breeze'
        shutil.copytree(BOOTSTRAP, self.root)
        self.cache = self.base / 'Caches/Shengjian/Breeze'
        self.fixture = self.base / 'upstream'
        for name in ['breeze_infer/api.py', 'models/model.py', 'configs/fast.json', 'LICENSE',
                     'requirements-mac-overrides.txt', 'tests/not-runtime.py', 'docs/not-runtime.md']:
            path = self.fixture / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        (self.fixture / 'requirements.txt').write_text('numpy>=2.0\npytest>=8.0\nruff>=0.12\n')
        tools = self.root / 'tools'
        tools.mkdir()
        for name in ['git', 'uv', 'curl']:
            path = tools / name
            path.write_text(TOOL.format(python=sys.executable, revision=REVISION))
            path.chmod(0o755)
        self.log = self.base / 'commands.jsonl'
        self.env = dict(os.environ, BREEZE_CACHE_ROOT=str(self.cache),
                        BREEZE_TEST_LOG=str(self.log), BREEZE_TEST_FIXTURE=str(self.fixture))

    def install(self, **environment):
        return subprocess.run(['/bin/bash', str(self.root / 'setup.sh')],
                              env=dict(self.env, **environment), text=True, capture_output=True)

    def assert_staging_clean(self):
        self.assertFalse((self.root / 'data/install.lock').exists())
        self.assertEqual(list((self.cache / 'tmp').iterdir()), [])

    def test_install_and_repair_keep_only_runtime_files(self):
        runtime = self.root / 'runtime'
        (runtime / '.venv').mkdir(parents=True)
        sentinel = runtime / '.venv/existing-environment'
        sentinel.write_text('preserve')
        for _ in range(2):
            result = self.install()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assert_staging_clean()
        self.assertEqual(sentinel.read_text(), 'preserve')
        self.assertEqual((runtime / '.source-revision').read_text().strip(), REVISION)
        self.assertEqual({p.name for p in runtime.iterdir()}, {
            '.venv', '.source-revision', 'breeze_infer', 'models', 'configs', 'LICENSE',
            'requirements.txt', 'requirements-mac-overrides.txt'})
        commands = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(sum(name == 'git' and args[0] == 'clone' for name, args in commands), 1)
        self.assertEqual(sum(name == 'hf' for name, args in commands), 2)
        self.assertTrue((self.root / 'data/huggingface').is_dir())
        for name in ['uv-cache', 'cache', 'tmp']:
            self.assertFalse((self.root / 'data' / name).exists())
        self.assertTrue((self.cache / 'uv').is_dir())

    def test_failed_install_releases_lock_and_removes_staging(self):
        result = self.install(BREEZE_TEST_FAIL='1')
        self.assertEqual(result.returncode, 12, result.stdout + result.stderr)
        self.assert_staging_clean()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_running_service_blocks_install_before_changing_runtime(self):
        result = self.install(BREEZE_TEST_ACTIVE='1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('请先在语音合成页停止服务', result.stdout)
        self.assertFalse((self.root / 'runtime').exists())
        self.assert_staging_clean()


if __name__ == '__main__':
    unittest.main()
