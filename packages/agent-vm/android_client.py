"""Lease-local ADB server and loopback device bridge for SDK clients."""

import json
import os
import select
import shlex
import shutil
import socket
import socketserver
import subprocess
import sys
import threading
import time

from agent_vm import connect, rpc
from android_vm import bridge_pair
from broker import Rejected


def sdk_environment(port, serial):
    return {
        "ADB_SERVER_SOCKET": f"tcp:127.0.0.1:{port}",
        "ANDROID_ADB_SERVER_PORT": str(port),  # ddmlib/Gradle
        "ANDROID_SERIAL": serial,
    }


def adb_env(path, token, directory):
    adb = shutil.which("adb")
    if not adb:
        raise Rejected("adb (Android SDK platform-tools) must be on PATH")
    generation = rpc(path, token, "adb-env", target="android")["generation"]
    with (directory / "adb.log").open("w") as log:
        process = subprocess.Popen(
            [sys.executable, __file__, path, generation, adb],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=log,
            start_new_session=True,
        )
    with process.stdin, process.stdout:
        process.stdin.write(token.encode())
        process.stdin.close()
        line = process.stdout.readline()
    if not line:
        process.wait(timeout=10)
        raise Rejected(f"ADB setup failed; see {directory / 'adb.log'}")
    for name, value in json.loads(line).items():
        print(f"export {name}={shlex.quote(value)}")


def serve(path, token, generation, adb):
    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            try:
                with connect(path, token, "adb-proxy", generation=generation)[
                    0
                ] as guest:
                    guest.settimeout(None)
                    bridge_pair(self.request, guest)
            except (Rejected, OSError):
                pass

    class Bridge(socketserver.ThreadingTCPServer):
        daemon_threads = True
        request_queue_size = 8

    with (
        connect(path, token, "adb-watch", generation=generation)[0] as watcher,
        Bridge(("127.0.0.1", 0), Handler) as bridge,
    ):
        watcher.settimeout(None)
        serial = f"127.0.0.1:{bridge.server_address[1]}"
        # ADB needs its own port even if there is another SDK in this container.
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        environment = sdk_environment(port, serial)
        env = {**os.environ, **environment, "ADB_MDNS_AUTO_CONNECT": "0"}
        adb_server = subprocess.Popen(
            [adb, "-L", f"tcp:{port}", "nodaemon", "server"],
            stdin=subprocess.DEVNULL,
            stdout=sys.stderr,
            env=env,
        )
        threading.Thread(target=bridge.serve_forever, daemon=True).start()
        try:
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline and adb_server.poll() is None:
                if select.select([watcher], [], [], 0.1)[0]:
                    raise Rejected("Android lease ended during ADB setup")
                try:
                    with socket.create_connection(
                        ("127.0.0.1", port), timeout=0.5
                    ) as probe:
                        probe.sendall(b"000chost:version")
                        if probe.recv(4, socket.MSG_WAITALL) == b"OKAY":
                            break
                except OSError:
                    pass
            else:
                raise Rejected("ADB server did not start")

            def call(*arguments):
                return (
                    subprocess.check_output(
                        [adb, *arguments], stderr=subprocess.STDOUT, timeout=8, env=env
                    )
                    .decode()
                    .strip()
                )

            print(call("connect", serial), file=sys.stderr)
            call("-s", serial, "wait-for-device")
            if call("-s", serial, "get-state") != "device":
                raise Rejected("ADB device is not ready")
            print(json.dumps(environment), flush=True)
            sys.stdout.close()
            while (
                adb_server.poll() is None and not select.select([watcher], [], [], 1)[0]
            ):
                pass
        finally:
            adb_server.terminate()
            try:
                adb_server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                adb_server.kill()
                adb_server.wait()


if __name__ == "__main__":
    try:
        path, generation, adb = sys.argv[1:]
        serve(path, sys.stdin.read(), generation, adb)
    except (OSError, Rejected, subprocess.SubprocessError) as error:
        print(f"agent-vm: {error}", file=sys.stderr)
        sys.exit(1)
