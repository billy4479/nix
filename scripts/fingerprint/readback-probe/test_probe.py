"""Offline flow/privacy tests. The executable uses mock_transport.c, never SPI."""

import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())
cases = {
    "success": (0, [0, 2, 3]),
    "echoed_hash_tag": (0, [0, 2, 3]),
    "stale_hash": (0, [0, 2, 3]),
    "stale_version": (0, [0, 2, 3]),
    "partial_then_ack": (0, [0, 2, 3]),
    "wrong_version": (2, [0]),
    "denied_hash": (2, [0, 2]),
    "denied_wrapped": (2, [0, 2, 3]),
    "hash_only": (2, [0, 2, 3]),
    "wrong_tag": (2, [0, 2]),
    "corrupt_checksum": (2, [0, 2]),
    "length_mismatch": (1, [0, 2]),
    "short_hash": (2, [0, 2]),
    "empty_blob": (2, [0, 2, 3]),
    "io_error": (1, [0, 2]),
}
cases["hash_diagnostic"] = (0, [0, 2])
for scenario, (code, queries) in cases.items():
    diagnostic = scenario == "hash_diagnostic"
    args = ["--check-hash"] if diagnostic else []
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        result = subprocess.run(
            [binary, *args, "/dev/mock-not-a-real-device"],
            cwd=path,
            env={**os.environ, "SCENARIO": "success" if diagnostic else scenario},
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == code, (scenario, result.stdout, result.stderr)
        observed = list(map(int, (path / "mock-queries.txt").read_text().splitlines()))
        assert observed == queries, (scenario, observed)
        assert not any(
            line.startswith(("rx=", "tx=", "status="))
            for line in result.stdout.splitlines()
        ), scenario
        assert "a5" * 16 not in result.stdout + result.stderr, scenario
        for name in ("raw-spi.txt", "mcu-state.bin", "key-hash.bin", "wrapped-key.bin"):
            if (path / name).exists():
                assert stat.S_IMODE((path / name).stat().st_mode) == 0o600
        assert not (path / "mcu-state.bin").exists()
        assert "mcu_state=not_requested" in result.stdout
        if scenario == "stale_hash":
            assert "query_3_foreign=1" in result.stdout
        if scenario == "stale_version":
            assert "query_0_foreign=1" in result.stdout
        if scenario in (
            "success",
            "echoed_hash_tag",
            "stale_hash",
            "stale_version",
            "partial_then_ack",
        ):
            assert len((path / "key-hash.bin").read_bytes()) == 32
            assert len((path / "wrapped-key.bin").read_bytes()) == 102
        if scenario == "hash_only":
            assert "key_hash=collected" in result.stdout
            assert "query_3_foreign=1" in result.stdout
            assert "result=wrapped_key_unavailable" in result.stdout
            assert not (path / "wrapped-key.bin").exists()
        if diagnostic:
            assert "result=hash_preflight_passed" in result.stdout
            assert len((path / "key-hash.bin").read_bytes()) == 32
            assert "query=2" in (path / "raw-spi.txt").read_text()
        if 3 not in queries:
            assert not (path / "wrapped-key.bin").exists()

# Pre-existing paths must not be followed or overwritten, including by root.
for name in ("raw-spi.txt", "key-hash.bin"):
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        target = path / "sentinel"
        target.write_bytes(b"DO NOT OVERWRITE")
        (path / name).symlink_to(target)
        result = subprocess.run(
            [binary, "/dev/mock-not-a-real-device"],
            cwd=path,
            env={**os.environ, "SCENARIO": "success"},
            capture_output=True,
        )
        assert result.returncode == 1
        assert target.read_bytes() == b"DO NOT OVERWRITE"
        assert not (path / "wrapped-key.bin").exists()
print(
    "Offline flow tests passed: canonical/echoed tags, stale hash filtering, no state query, refusals, private files and symlinks."
)
