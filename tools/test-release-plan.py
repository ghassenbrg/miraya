#!/usr/bin/env python3
"""Exercise release guards in a disposable Git repo; never writes to this checkout."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleasePlanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="miraya-release-plan-")
        self.repo = Path(self.directory.name)
        (self.repo / "scripts/ci").mkdir(parents=True)
        shutil.copy(ROOT / "scripts/ci/release-plan.sh", self.repo / "scripts/ci/release-plan.sh")
        (self.repo / "VERSION").write_text("0.1.0\n")
        self.git("init", "-b", "master")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture")

    def tearDown(self):
        self.directory.cleanup()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, capture_output=True, text=True, check=True)

    def plan(self, **overrides):
        env = os.environ.copy()
        for key in ("CHANNEL", "SIGNING", "ANDROID_SIGNING", "GITHUB_REF"):
            env.pop(key, None)
        env.update(overrides)
        return subprocess.run(["bash", "scripts/ci/release-plan.sh"], cwd=self.repo, env=env, capture_output=True, text=True)

    def test_snapshot_without_keys(self):
        result = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tag=v0.1.0-snapshot.1\n", result.stdout)
        self.assertIn("prerelease=true\n", result.stdout)

    def test_production_requires_both_platforms(self):
        self.assertNotEqual(self.plan(CHANNEL="production").returncode, 0)
        self.assertNotEqual(self.plan(CHANNEL="production", SIGNING="yes").returncode, 0)
        result = self.plan(CHANNEL="production", SIGNING="yes", ANDROID_SIGNING="yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tag=v0.1.0\n", result.stdout)
        self.assertIn("prerelease=false\n", result.stdout)

    def test_tag_must_match_version_and_channel(self):
        env = dict(SIGNING="yes", ANDROID_SIGNING="yes")
        self.assertNotEqual(self.plan(GITHUB_REF="refs/tags/v9.0.0", **env).returncode, 0)
        self.assertNotEqual(self.plan(GITHUB_REF="refs/tags/v0.1.0", CHANNEL="snapshot", **env).returncode, 0)
        self.assertEqual(self.plan(GITHUB_REF="refs/tags/v0.1.0", **env).returncode, 0)

    def test_unknown_channel_rejected(self):
        self.assertNotEqual(self.plan(CHANNEL="preview").returncode, 0)

    def test_cannot_move_production_tag_to_another_commit(self):
        self.git("tag", "v0.1.0")
        (self.repo / "change").write_text("another commit\n")
        self.git("add", "change")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "later")
        result = self.plan(CHANNEL="production", SIGNING="yes", ANDROID_SIGNING="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already marks another commit", result.stderr)


if __name__ == "__main__":
    unittest.main()
