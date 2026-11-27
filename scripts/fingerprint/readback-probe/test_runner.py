"""Exercise report preservation/cleanup without running the privileged entrypoint.

Only finish() is loaded. The sensor is a temporary directory, never /sys;
module-load/unbind paths are disabled. No SPI or real privileged operations.
"""

import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

runner = Path(sys.argv[1]).read_text()
finish = runner[runner.index("finish() {") : runner.index("trap 'finish' EXIT")]
for kind in ("version", "readback", "provision"):
    for failure in (False, True):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            for name in ("work", "home", "sensor"):
                (path / name).mkdir(mode=0o700)
            (path / "work/before").write_text("messages=0\n")
            (path / "work/probe.log").write_text(
                "firmware=GF_ITE_EC_20066\nresult=test_only\n"
            )
            (path / "work/raw-spi.txt").write_text("SYNTHETIC_PRIVATE_DATA")
            (path / "sensor/driver_override").write_text("spidev\n")
            if failure:
                (path / "sensor/driver").symlink_to(path / "unexpected-driver")
            script = (
                """
set -euo pipefail
umask 077
work=$PWD/work
user_home=$PWD/home
sensor=$PWD/sensor
release=test-kernel
node=not-created
SUDO_UID=$(id -u)
SUDO_GID=$(id -g)
override_set=1
binding_attempted=0
loaded_spidev=0
snapshot() { printf 'messages=0\\n'; }
"""
                + finish
                + "\nfinish\n"
            )
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=path,
                env={**os.environ, "kind": kind},
                text=True,
                capture_output=True,
            )
            assert result.returncode == int(failure), result.stderr
            assert "SYNTHETIC_PRIVATE_DATA" not in result.stdout + result.stderr
            assert not (path / "work").exists()
            assert (path / "sensor/driver_override").read_text() == "\n"
            (report,) = (path / "home").iterdir()
            assert stat.S_IMODE(report.stat().st_mode) == 0o600
            if kind != "version":
                import tarfile

                with tarfile.open(report) as archive:
                    assert (
                        archive.extractfile("./raw-spi.txt").read()
                        == b"SYNTHETIC_PRIVATE_DATA"
                    )
                    text = archive.extractfile("./report.txt").read().decode()
            else:
                text = report.read_text()
            assert f"cleanup_failed={int(failure)}" in text
print(
    "Runner tests passed: all report formats, private data/permissions, override restoration and cleanup failure reporting (all filesystem state is fake)."
)
