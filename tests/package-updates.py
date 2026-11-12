"""Check updater discovery and repository paths without contacting upstreams."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(sys.argv.pop(1)).resolve()


class PackageUpdates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.packages = self.root / "packages"
        (self.packages / "lib").mkdir(parents=True)
        shutil.copy(SOURCE / "update.sh", self.packages)
        shutil.copy(SOURCE / "lib/update-common.sh", self.packages / "lib")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.log = self.root / "called"
        self.env = {**os.environ, "UPDATE_TEST_LOG": str(self.log)}
        for name, status in [("alpha", 0), ("beta", 1), ("gamma", 0)]:
            directory = self.packages / name
            directory.mkdir()
            script = directory / "update.sh"
            script.write_text(
                f"#!{shutil.which('bash')}\n"
                'source "$(dirname "$0")/../lib/update-common.sh"\n'
                'cd "$(update_repo_root)"\n'
                "test -d packages/lib || exit 99\n"
                f'echo {name} >> "$UPDATE_TEST_LOG"\n'
                f"exit {status}\n"
            )
            script.chmod(0o755)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=Package update tests",
                "-c",
                "user.email=tests@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-qm",
                "Initialize fixtures",
            ],
            check=True,
        )

    def run_updates(self, *names, cwd=None):
        return subprocess.run(
            ["bash", str(self.packages / "update.sh"), *names],
            cwd=cwd or self.root,
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_discovers_packages_and_continues_after_failure(self):
        result = self.run_updates()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["alpha", "beta", "gamma"])
        self.assertIn("failed packages: beta", result.stderr)

    def test_skips_modified_packages_and_continues(self):
        script = self.packages / "alpha/update.sh"
        modified = script.read_text() + "# Local change\n"
        script.write_text(modified)

        result = self.run_updates("alpha", "gamma")

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("alpha: has local changes, skipping", result.stderr)
        self.assertIn("failed packages: alpha", result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["gamma"])
        self.assertEqual(script.read_text(), modified)

    def test_subset_from_outside_repository(self):
        result = self.run_updates("gamma", "alpha", cwd=self.root.parent)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["gamma", "alpha"])


if __name__ == "__main__":
    unittest.main()
