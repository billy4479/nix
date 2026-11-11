"""Offline tests for Actions deploy-key routing: python3 tests/ci-ssh.py."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ci-ssh.sh"
REPOSITORIES = {
    "NIX_SECRETS_DEPLOY_KEY": "nix-secrets",
    "FF_DEPLOY_KEY": "ff",
    "CALENDAR_PROXY_DEPLOY_KEY": "calendar-proxy-v2",
    "GIUOCO_DEL_DIVERTIMENTO_DEPLOY_KEY": "giuoco-del-divertimento",
    "QUOTE_BOT_DEPLOY_KEY": "quote-bot",
}


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "GIT_CONFIG_GLOBAL": str(self.home / ".gitconfig"),
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        for variable, repository in REPOSITORIES.items():
            key = self.home / repository
            subprocess.run(
                [
                    "ssh-keygen",
                    "-q",
                    "-t",
                    "ed25519",
                    "-N",
                    "",
                    "-C",
                    "generic-comment",
                    "-f",
                    str(key),
                ],
                check=True,
            )
            self.env[variable] = key.read_text()

    def test_each_repository_uses_only_its_own_key(self):
        subprocess.run(["bash", str(SCRIPT)], env=self.env, check=True)
        config = self.home / ".ssh/config"
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        for variable, repository in REPOSITORIES.items():
            with self.subTest(repository=repository):
                alias = f"github-ci-{repository}"
                for url in (
                    f"ssh://git@github.com/billy4479/{repository}.git",
                    f"git@github.com:billy4479/{repository}.git",
                ):
                    rewritten = subprocess.check_output(
                        ["git", "ls-remote", "--get-url", url], env=self.env, text=True
                    ).strip()
                    self.assertEqual(
                        rewritten, f"ssh://git@{alias}/billy4479/{repository}.git"
                    )
                settings = subprocess.check_output(
                    ["ssh", "-G", "-F", str(config), alias],
                    text=True,
                    stderr=subprocess.DEVNULL,
                ).splitlines()
                self.assertIn("hostname github.com", settings)
                self.assertIn("identitiesonly yes", settings)
                self.assertIn("batchmode yes", settings)
                identities = [s for s in settings if s.startswith("identityfile ")]
                key = self.home / ".ssh" / f"ci-{repository}"
                self.assertEqual(identities, [f"identityfile {key}"])
                self.assertEqual(key.read_text().strip(), self.env[variable].strip())
                self.assertEqual(key.stat().st_mode & 0o777, 0o600)

    def test_missing_secret_fails_without_disclosing_keys(self):
        del self.env["CALENDAR_PROXY_DEPLOY_KEY"]
        result = subprocess.run(
            ["bash", str(SCRIPT)], env=self.env, capture_output=True, text=True
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Missing Actions secret: CALENDAR_PROXY_DEPLOY_KEY", result.stderr
        )
        self.assertNotIn("PRIVATE KEY", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
