"""Validate the generated production TOML and evaluate it with real direnv."""

import json
import os
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path


class DirenvConfigTest(unittest.TestCase):
    def test_generated_configs_load_and_reject_failed_environments(self):
        configuration = Path(os.environ["TEST_DIRENV_CONFIG"])
        binary = os.environ["TEST_DIRENV"]
        for scope in ["manual", "trusted"]:
            with self.subTest(scope=scope), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                config_dir = configuration / scope
                parsed = tomllib.loads((config_dir / "direnv.toml").read_text())
                self.assertTrue(parsed["global"]["strict_env"])
                if scope == "trusted":
                    self.assertEqual(
                        parsed["whitelist"]["prefix"],
                        ["/workspace/code/", "/workspace/nix/"],
                    )
                else:
                    self.assertNotIn("whitelist", parsed)
                env = {
                    **os.environ,
                    "HOME": str(root),
                    "DIRENV_CONFIG": str(config_dir),
                    "XDG_DATA_HOME": str(root / "data"),
                }
                env.pop("DIRENV_DIFF", None)
                env.pop("DIRENV_DIR", None)
                env.pop("DIRENV_FILE", None)
                envrc = root / ".envrc"
                envrc.write_text("export GENERATED_CONFIG_TEST=loaded\n")
                subprocess.run(
                    [binary, "allow", str(root)],
                    env=env,
                    cwd=root,
                    check=True,
                    capture_output=True,
                )
                result = subprocess.run(
                    [binary, "export", "json"],
                    env=env,
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(
                    json.loads(result.stdout)["GENERATED_CONFIG_TEST"], "loaded"
                )
                envrc.write_text("return 1\n")
                subprocess.run(
                    [binary, "allow", str(root)],
                    env=env,
                    cwd=root,
                    check=True,
                    capture_output=True,
                )
                failed = subprocess.run(
                    [
                        binary,
                        "exec",
                        str(root),
                        os.environ["TEST_BASH"],
                        "-c",
                        "echo MUST_NOT_RUN",
                    ],
                    env=env,
                    cwd=root,
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(failed.returncode, 0)
                self.assertNotIn("MUST_NOT_RUN", failed.stdout)


if __name__ == "__main__":
    unittest.main()
