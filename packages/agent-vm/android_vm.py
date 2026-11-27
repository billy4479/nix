"""Host Android backend and the unprivileged emulator service entry point."""

import logging
import os
import secrets
import shutil
import socket
import socketserver
import subprocess
import threading
import time
from pathlib import Path

from broker import disconnect, relay

DEVICE = ("127.0.0.1", 5555)
TRANSPORT = Path("/run/agent-android/adb.sock")
UNIT = "agent-android.service"
AVD_NAME = "agent"


class AndroidVM:
    def __init__(self, storage):
        self.state = Path(storage) / "android"
        self.generation = None

    def clean(self, force=False):
        # Wait for the whole service cgroup to stop, not just the launcher.
        subprocess.run(["systemctl", "stop", UNIT], check=True, timeout=25)
        try:
            shutil.rmtree(self.state)
        except FileNotFoundError:
            pass
        self.generation = None

    def start(self):
        subprocess.run(["systemctl", "start", UNIT], check=True, timeout=135)
        self.generation = secrets.token_hex(16)

    def credentials(self):
        return {"generation": self.generation}

    def connect(self, timeout):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.settimeout(timeout)
            sock.connect(str(TRANSPORT))
            return sock
        except BaseException:
            sock.close()
            raise


def bridge_pair(left, right):
    outgoing = threading.Thread(target=relay, args=(left, right), daemon=True)
    outgoing.start()
    try:
        relay(right, left)
    finally:
        disconnect(left, right)
        outgoing.join()


class DeviceProxy(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            with socket.create_connection(DEVICE, timeout=2) as device:
                device.settimeout(None)
                bridge_pair(self.request, device)
        except OSError:
            pass


class DeviceServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True


def configure_avd(state, sdk):
    avds = state / "avd"
    avd = avds / f"{AVD_NAME}.avd"
    avd.mkdir(parents=True, exist_ok=True)
    image = sdk / "system-images/android-35/default/x86_64"
    if not (image / "system.img").is_file():
        raise RuntimeError(f"missing Android system image: {image}")
    (avds / f"{AVD_NAME}.ini").write_text(
        f"avd.ini.encoding=UTF-8\npath={avd}\ntarget=android-35\n"
    )
    (avd / "config.ini").write_text(
        f"AvdId={AVD_NAME}\n"
        f"image.sysdir.1={image}/\n"
        "abi.type=x86_64\n"
        "hw.cpu.arch=x86_64\n"
        "tag.id=default\n"
        "hw.ramSize=2048\n"
        "hw.cpu.ncore=2\n"
        "hw.lcd.width=1080\n"
        "hw.lcd.height=1920\n"
        "hw.lcd.density=420\n"
        "hw.keyboard=yes\n"
        "disk.dataPartition.size=4G\n"
    )
    os.environ.update(
        HOME=str(state),
        ANDROID_HOME=str(sdk),
        ANDROID_AVD_HOME=str(avds),
    )


def run_emulator(state, sdk):
    logging.basicConfig(level=logging.INFO)
    configure_avd(state, sdk)
    emulator = sdk / "emulator/emulator"
    adb = str(sdk / "platform-tools/adb")
    subprocess.run([emulator, "-accel-check"], timeout=10, check=True)
    with subprocess.Popen(
        [
            emulator,
            "-avd",
            AVD_NAME,
            "-port",
            "5554",
            "-accel",
            "on",
            "-no-window",
            "-no-audio",
            "-no-boot-anim",
            "-no-snapshot",
            "-gpu",
            "swiftshader",
            "-dns-server",
            "1.1.1.1,9.9.9.9",
            "-skip-adb-auth",
            "-adb-path",
            adb,
        ],
        stdin=subprocess.DEVNULL,
    ) as process:

        def ready(*arguments):
            try:
                return subprocess.check_output(
                    [adb, "-s", "emulator-5554", *arguments],
                    timeout=3,
                    stderr=subprocess.DEVNULL,
                ).strip()
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                return b""

        try:
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline and process.poll() is None:
                if ready("shell", "getprop", "sys.boot_completed") == b"1" and ready(
                    "shell", "pm", "path", "android"
                ).startswith(b"package:"):
                    break
                time.sleep(1)
            else:
                raise RuntimeError("Android did not boot within the service deadline")
            # Free the emulator transport for the lease's own ADB server.
            subprocess.run([adb, "kill-server"], timeout=5, check=True)
            with DeviceServer(str(TRANSPORT), DeviceProxy) as server:
                server.timeout = 0.5
                subprocess.run(["systemd-notify", "--ready"], timeout=5, check=True)
                while process.poll() is None:
                    server.handle_request()
                raise RuntimeError(f"Android emulator exited: {process.returncode}")
        finally:
            if process.poll() is None:
                process.kill()
