"""Check shared skill discovery against real OpenCode, with an isolated server."""

import json
import os
import secrets
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


class OpenCodeTest(unittest.TestCase):
    def test_symlink_discovery_and_reload_after_atomic_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            skill = root / "shared/skills/shared-check/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text(
                "---\nname: shared-check\ndescription: First description\n---\nShared instructions\n"
            )
            (root / "config/opencode").mkdir(parents=True)
            (root / "home").mkdir()
            (root / "config/opencode/skills").symlink_to(root / "shared/skills")
            env = {
                key: value
                for key, value in os.environ.items()
                if not key.startswith(("OPENCODE_", "XDG_"))
            }
            env.update(
                HOME=str(root / "home"),
                XDG_CONFIG_HOME=str(root / "config"),
                XDG_DATA_HOME=str(root / "data"),
                XDG_STATE_HOME=str(root / "state"),
                XDG_CACHE_HOME=str(root / "cache"),
                OPENCODE_SERVER_PASSWORD=secrets.token_urlsafe(),
            )
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            binary = os.environ["TEST_OPENCODE"]
            origin = f"http://127.0.0.1:{port}"

            def request(method, route):
                return subprocess.run(
                    [binary, "api", "--server", origin, method, route],
                    cwd=root,
                    env=env,
                    capture_output=True,
                    check=False,
                    text=True,
                    timeout=15,
                )

            def await_skill(description):
                # The registry initially contains built-ins while config plugins
                # initialize. Keep the same server alive until discovery settles.
                deadline = time.monotonic() + 45
                while time.monotonic() < deadline:
                    self.assertIsNone(server.poll())
                    result = request("get", "/api/skill")
                    if result.returncode == 0:
                        skills = [
                            s
                            for s in json.loads(result.stdout)["data"]
                            if s["id"] == "shared-check"
                        ]
                        if len(skills) == 1 and skills[0]["description"] == description:
                            return
                    time.sleep(0.1)
                self.fail("OpenCode did not discover the shared skill exactly once")

            # Never emit the disposable server credential or its logs.
            with (root / "server.log").open("w") as log:
                server = subprocess.Popen(
                    [binary, "serve", "--hostname", "127.0.0.1", "--port", str(port)],
                    cwd=root,
                    env=env,
                    stdout=log,
                    stderr=log,
                )
                try:
                    await_skill("First description")
                    replacement = skill.with_suffix(".new")
                    replacement.write_text(
                        "---\nname: shared-check\ndescription: Updated description\n---\nUpdated instructions\n"
                    )
                    replacement.replace(skill)
                    self.assertEqual(
                        request("post", "/api/location/reload").returncode, 0
                    )
                    await_skill("Updated description")
                finally:
                    server.terminate()
                    server.wait(timeout=20)


if __name__ == "__main__":
    unittest.main()
