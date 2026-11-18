import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
GUARD = ROOT / '.gitlab' / 'opentofu' / 'apply_guard.sh'


class ApplyGuardTests(unittest.TestCase):
    def run_guard(self, remote, commit='a' * 40, branch='main'):
        with tempfile.TemporaryDirectory() as directory:
            git = pathlib.Path(directory) / 'git'
            git.write_text('#!/bin/sh\nprintf "%s\\trefs/heads/main\\n" "$REMOTE_SHA"\n')
            git.chmod(0o755)
            env = dict(os.environ, PATH=f'{directory}:{os.environ["PATH"]}',
                       CI_COMMIT_SHA=commit, CI_DEFAULT_BRANCH='main',
                       CI_COMMIT_BRANCH=branch, REMOTE_SHA=remote)
            return subprocess.run(['sh', str(GUARD)], env=env, capture_output=True)

    def test_accepts_current_main_commit(self):
        self.assertEqual(self.run_guard('a' * 40).returncode, 0)

    def test_rejects_superseded_main_commit(self):
        self.assertNotEqual(self.run_guard('b' * 40).returncode, 0)

    def test_rejects_missing_remote_head(self):
        self.assertNotEqual(self.run_guard('').returncode, 0)

    def test_rejects_non_default_branch(self):
        self.assertNotEqual(self.run_guard('a' * 40, branch='feature').returncode, 0)


if __name__ == '__main__':
    unittest.main()
