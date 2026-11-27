"""Exercise the provisioning flow against the fake sensor transport.

The binary runs in a temporary private directory. The key is real random data
but never leaves that directory; no SPI device, ioctl or kernel path is used.
"""

import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())
key_name = "fingerprint-gxfp5120.psk"
scenarios = {
    "volatile_fs": (1, set()),
    "existing_key": (1, set()),
    "symlink_key": (1, set()),
    "key_write_failed": (1, {"result=recovery_storage_failed_no_upload"}),
    "key_sync_failed": (1, {"result=recovery_storage_failed_no_upload"}),
    "directory_sync_failed": (1, {"result=recovery_storage_failed_no_upload"}),
    "interrupted_upload": (99, {"new_key=durably_saved"}),
    "success": (0, {"result=key_replaced_verified", "key_hash=verified"}),
    "hash_stale": (0, {"result=key_replaced_verified", "key_hash=verified"}),
    "hash_retry": (0, {"result=key_replaced_verified"}),
    "hash_silent": (2, {"result=existing_hash_unavailable_stop"}),
    "no_completion": (
        2,
        {
            "write_ack=yes",
            "write_completion=no",
            "key_hash=verified",
            "result=key_replaced_completion_unconfirmed",
        },
    ),
    "status": (
        2,
        {
            "write_ack=yes",
            "write_completion=yes",
            "write_status=7",
            "key_hash=mismatch",
            "result=key_write_failed_existing_hash_unchanged",
        },
    ),
    "status_changed": (
        2,
        {
            "write_ack=yes",
            "write_completion=yes",
            "write_status=7",
            "key_hash=mismatch",
            "observed_hash=changed_not_new",
            "result=key_write_failed_hash_changed_not_new",
        },
    ),
    "no_ack": (
        2,
        {
            "write_ack=no",
            "write_completion=no",
            "key_hash=mismatch",
            "result=key_write_failed_existing_hash_unchanged",
        },
    ),
    "hash_mismatch": (
        2,
        {
            "write_ack=yes",
            "write_completion=yes",
            "write_status=0",
            "key_hash=mismatch",
            "result=key_replacement_unverified",
        },
    ),
    "hash_without_ack": (
        2,
        {"hash_ack=no", "result=existing_hash_unavailable_stop"},
    ),
    "existing_hash_refused": (
        2,
        {
            "hash_status=7",
            "result=existing_hash_unavailable_stop",
        },
    ),
}
no_baseline = {"existing_hash_refused", "hash_without_ack", "hash_silent"}
for scenario, (expected_code, expected) in scenarios.items():
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp)
        recovery = path / "recovery"
        recovery.mkdir(mode=0o700)
        key = recovery / key_name
        if scenario == "existing_key":
            key.write_bytes(b"known existing key")
        if scenario == "symlink_key":
            key.symlink_to("missing-target")
        result = subprocess.run(
            [binary, "--replace-psk", "/dev/fake-sensor"],
            cwd=path,
            env={**os.environ, "SCENARIO": scenario},
            text=True,
            capture_output=True,
        )
        assert result.returncode == expected_code, (scenario, result)
        for line in expected:
            assert line in result.stdout, (scenario, line)
        scratch = set(path.iterdir()) - {recovery}
        if scenario in {"volatile_fs", "existing_key", "symlink_key"}:
            assert not scratch and "profile=" not in result.stdout
        elif scenario in no_baseline:
            assert not scratch
        else:
            assert scratch == {path / "before-hash.bin"}
            assert stat.S_IMODE((path / "before-hash.bin").stat().st_mode) == 0o600
        if scenario == "existing_key":
            assert key.read_bytes() == b"known existing key"
        if scenario == "symlink_key":
            assert key.is_symlink() and not (recovery / "missing-target").exists()
        if scenario == "volatile_fs" or scenario in no_baseline:
            assert not key.exists()
        assert result.stdout.count("hash_retry=") == int(
            scenario in {"hash_retry", "hash_silent"}
        )
        if expected_code == 1 or scenario in no_baseline:
            assert "write_fragments=" not in result.stdout
            assert "new_key=durably_saved" not in result.stdout
            continue

        psk = key.read_bytes()
        assert len(psk) == 32 and any(psk)
        assert stat.S_IMODE(key.stat().st_mode) == 0o600
        assert psk.hex() not in result.stdout + result.stderr
        if scenario == "interrupted_upload":
            # The same retained key blocks a second attempt, before any SPI.
            retry = subprocess.run(
                [binary, "--replace-psk", "/dev/fake-sensor"],
                cwd=path,
                text=True,
                capture_output=True,
            )
            assert retry.returncode == 1 and "profile=" not in retry.stdout
            assert key.read_bytes() == psk
        else:
            assert "write_fragments=1" in result.stdout
print(
    "Mock provisioning passed: durable storage ordering, fault handling, interruption, bounded hash retry, and protocol outcomes."
)
