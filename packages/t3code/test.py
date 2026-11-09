import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.request import urlopen

package = Path(sys.argv[1])
version = sys.argv[2]
command = package / "bin/t3"
runtime = package / "lib/t3code"

assert (
    subprocess.check_output([command, "--version"], text=True).strip()
    == f"t3 v{version}"
)
assert not (package / "bin/t3code-desktop").exists()
assert not list(runtime.rglob("*.map"))
assert not [p for p in runtime.rglob("*") if p.is_symlink() and not p.exists()]

# Exercise the compiled PTY, not just the JavaScript loader.
subprocess.run(
    [
        "node",
        "--input-type=module",
        "-e",
        """
import pty from './node_modules/node-pty/lib/index.js';
await import('@ff-labs/fff-node');
await import('@napi-rs/keyring');
await import('ffi-rs');
const term = pty.spawn(process.argv[1], ['-c', 'printf t3-pty-ok'], { env: process.env });
let output = '';
term.onData(data => { output += data; });
term.onExit(({ exitCode }) => {
  if (exitCode !== 0 || !output.includes('t3-pty-ok')) process.exitCode = 1;
});
""",
        sys.argv[3],
    ],
    cwd=runtime,
    check=True,
    timeout=15,
)

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]

# Start without host tools: git and gh come from the wrapper, providers are optional.
env = {**os.environ, "PATH": "", "T3CODE_NO_BROWSER": "true"}
with open("server.log", "w+") as log:
    server = subprocess.Popen(
        [command, "--host", "127.0.0.1", "--port", str(port), "--base-dir", "state"],
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    try:
        deadline = time.monotonic() + 90
        while True:
            assert server.poll() is None, "server exited before serving the web client"
            try:
                with urlopen(f"http://127.0.0.1:{port}/", timeout=2) as response:
                    html = response.read().decode()
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.25)
        assert "<html" in html
        assets = re.findall(r'(?:src|href)="(/assets/[^\"]+)"', html)
        assert assets, "web client is missing its built assets"
        for asset in assets:
            with urlopen(f"http://127.0.0.1:{port}{asset}", timeout=10) as response:
                assert response.status == 200 and response.read()
    finally:
        server.terminate()
        server.wait(timeout=15)
        log.seek(0)
        print(log.read())
