"""Run the sensor-side protocol against a real OpenSSL TLS 1.2 PSK peer."""

import socket
import subprocess
import sys
import tempfile
from pathlib import Path

binary = Path(sys.argv[1]).resolve()
key = bytes(range(32))  # Synthetic only.
for matches in (True, False):
    with tempfile.TemporaryDirectory() as work, socket.socket() as listener:
        path = Path(work) / "test-psk.bin"
        path.write_bytes(key)
        path.chmod(0o600)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(5)
        client_key = key if matches else bytes(reversed(key))
        client = subprocess.Popen(
            [
                "openssl",
                "s_client",
                "-connect",
                f"127.0.0.1:{listener.getsockname()[1]}",
                "-tls1_2",
                "-cipher",
                "PSK-AES128-CBC-SHA256",
                "-psk",
                client_key.hex(),
                "-psk_identity",
                "Client_identity",
                "-quiet",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            with listener.accept()[0] as conn:
                fd = conn.fileno()
                result = subprocess.run(
                    [str(binary), str(fd)],
                    cwd=work,
                    pass_fds=(fd,),
                    capture_output=True,
                    text=True,
                    timeout=7,
                )
            assert result.returncode == (0 if matches else 2), result
            expected = "verified" if matches else "failed"
            assert f"result=tls_handshake_{expected}" in result.stdout, result
            assert key.hex() not in result.stdout + result.stderr
        finally:
            client.kill()
            client.wait()
print(
    "TLS bridge passed: OpenSSL peer accepted with matching PSK, rejected with wrong PSK."
)
