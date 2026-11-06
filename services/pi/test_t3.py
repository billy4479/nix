"""Exercise production T3 authentication with disposable local state, no model calls."""

import json
import os
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from setup import setup


class T3Test(unittest.TestCase):
    def test_production_authentication_and_persistent_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            shared = home / "shared"
            (shared / "skills").mkdir(parents=True)
            (shared / "AGENTS.md").write_text("Test instructions\n")
            setup(home, Path(os.environ["TEST_EXTENSIONS"]), shared)
            settings_file = home / ".t3/userdata/settings.json"
            settings = json.loads(settings_file.read_text())
            settings["providerInstances"]["pi"]["config"]["binaryPath"] = os.environ[
                "TEST_PI"
            ]
            settings_file.write_text(json.dumps(settings))
            env = {
                **os.environ,
                "HOME": str(home),
                "PI_CODING_AGENT_DIR": str(home / ".pi/agent"),
                "PI_OFFLINE": "1",
                "PI_TELEMETRY": "0",
                "T3CODE_NO_BROWSER": "true",
            }
            t3 = os.environ["TEST_T3"]
            base = home / ".t3"
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            origin = f"http://127.0.0.1:{port}"

            def request(route, token=None):
                headers = {"Authorization": f"Bearer {token}"} if token else {}
                with urlopen(
                    Request(origin + route, headers=headers), timeout=3
                ) as response:
                    return json.load(response)

            # Logs can contain test pairing credentials; never print them.
            with (home / "server.log").open("w") as log:

                def start():
                    server = subprocess.Popen(
                        [
                            t3,
                            "serve",
                            "--host",
                            "127.0.0.1",
                            "--port",
                            str(port),
                            "--base-dir",
                            str(base),
                        ],
                        cwd=home,
                        env=env,
                        stdout=log,
                        stderr=subprocess.STDOUT,
                    )
                    try:
                        deadline = time.monotonic() + 90
                        while True:
                            self.assertIsNone(
                                server.poll(), "T3 exited before readiness"
                            )
                            try:
                                descriptor = request("/.well-known/t3/environment")
                                self.assertTrue(descriptor["environmentId"])
                                self.assertTrue(descriptor["serverVersion"])
                                return server, descriptor
                            except OSError as error:
                                if isinstance(error, HTTPError):
                                    error.close()
                                if time.monotonic() >= deadline:
                                    raise
                                time.sleep(0.1)
                    except BaseException:
                        server.terminate()
                        server.wait(timeout=20)
                        raise

                server, first = start()
                try:
                    with self.assertRaises(HTTPError) as denied:
                        request("/api/projects")
                    self.assertEqual(denied.exception.code, 401)
                    denied.exception.close()
                    # Issue only a disposable test session. Keep the token in
                    # memory, out of logs and command-line arguments.
                    token = subprocess.check_output(
                        [
                            t3,
                            "auth",
                            "session",
                            "issue",
                            "--base-dir",
                            str(base),
                            "--token-only",
                        ],
                        cwd=home,
                        env=env,
                        text=True,
                        stderr=subprocess.DEVNULL,
                        timeout=30,
                    ).strip()
                    self.assertTrue(token)
                    request("/api/projects", token)
                finally:
                    server.terminate()
                    server.wait(timeout=20)
                server, second = start()
                try:
                    self.assertEqual(first["environmentId"], second["environmentId"])
                    request("/api/projects", token)
                    current = json.loads(settings_file.read_text())
                    self.assertEqual(
                        current["defaultModelSelection"]["instanceId"], "pi"
                    )
                    self.assertEqual(
                        current["textGenerationModelSelection"]["instanceId"], "pi"
                    )
                finally:
                    server.terminate()
                    server.wait(timeout=20)


if __name__ == "__main__":
    unittest.main()
