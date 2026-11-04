"""Exercise the real receiver and installer with a disposable certificate authority."""

import grp
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("certificates.py")
HOST = "derp.polpetta.online"


class CertificateTransferTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory()
        cls.root = Path(cls.workspace.name)
        cls.ca = cls.root / "ca.crt"
        cls.run_ssl(
            "req",
            "-x509",
            "-newkey",
            "ec",
            "-pkeyopt",
            "ec_paramgen_curve:P-256",
            "-nodes",
            "-days",
            "3",
            "-subj",
            "/CN=Test CA",
            "-keyout",
            str(cls.root / "ca.key"),
            "-out",
            str(cls.ca),
        )

    @classmethod
    def tearDownClass(cls):
        cls.workspace.cleanup()

    @staticmethod
    def run_ssl(*args):
        subprocess.run(
            ["openssl", *args],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=self.root)
        self.path = Path(self.directory.name)
        self.staging = self.path / "staging"
        self.installed = self.path / "installed"
        self.staging.mkdir()
        self.installed.mkdir()
        self.bin = self.path / "bin"
        self.bin.mkdir()
        self.calls = self.path / "calls"
        systemctl = self.bin / "systemctl"
        systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >>"$TEST_CALLS"\n')
        systemctl.chmod(0o755)
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "TEST_CALLS": str(self.calls),
        }

    def tearDown(self):
        self.directory.cleanup()

    def bundle(self, name=HOST, days=3, reuse_key=False):
        key = self.path / "leaf.key"
        csr = self.path / "leaf.csr"
        certificate = self.path / "leaf.crt"
        extension = self.path / "extensions"
        extension.write_text(f"subjectAltName=DNS:{name}\n")
        if not reuse_key:
            self.run_ssl(
                "genpkey",
                "-algorithm",
                "EC",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
                "-out",
                str(key),
            )
        self.run_ssl(
            "req", "-new", "-key", str(key), "-subj", f"/CN={name}", "-out", str(csr)
        )
        self.run_ssl(
            "x509",
            "-req",
            "-in",
            str(csr),
            "-CA",
            str(self.ca),
            "-CAkey",
            str(self.root / "ca.key"),
            "-CAcreateserial",
            "-days",
            str(days),
            "-extfile",
            str(extension),
            "-out",
            str(certificate),
        )
        return {
            "certificate": certificate.read_text() + self.ca.read_text(),
            "key": key.read_text(),
        }

    def command(self, action, data=None, success=True):
        args = [
            sys.executable,
            str(SCRIPT),
            action,
            "--staging-dir",
            str(self.staging),
            "--hostname",
            HOST,
            "--ca-file",
            str(self.ca),
        ]
        if action == "install":
            args += [
                "--install-dir",
                str(self.installed),
                "--group",
                grp.getgrgid(os.getgid()).gr_name,
            ]
        result = subprocess.run(
            args, input=data, capture_output=True, env=self.environment, check=False
        )
        self.assertEqual(result.returncode == 0, success, result.stderr.decode())
        if not success and data:
            # Rejected private key data must not appear in diagnostic output.
            self.assertNotIn(b"BEGIN PRIVATE KEY", result.stdout + result.stderr)
        return result

    def test_first_install_and_unchanged_upload(self):
        bundle = self.bundle()
        data = json.dumps(bundle).encode()
        self.command("receive", data)
        self.command("install")
        current = self.installed / "current"
        self.assertEqual((current / f"{HOST}.key").read_text(), bundle["key"])
        self.assertEqual((current / f"{HOST}.key").stat().st_mode & 0o777, 0o640)
        self.assertEqual(current.stat().st_mode & 0o777, 0o750)
        timestamp = (self.staging / "bundle.json").stat().st_mtime_ns
        self.command("receive", data)
        self.command("install")
        self.assertEqual((self.staging / "bundle.json").stat().st_mtime_ns, timestamp)
        self.assertEqual(
            self.calls.read_text(), "--no-block try-restart derper-derp.service\n"
        )

    def test_renewal_with_same_key_is_not_skipped(self):
        initial = self.bundle()
        self.command("receive", json.dumps(initial).encode())
        self.command("install")
        previous = (self.installed / "current").readlink()
        renewed = self.bundle(reuse_key=True)
        self.assertEqual(initial["key"], renewed["key"])
        self.assertNotEqual(initial["certificate"], renewed["certificate"])
        self.command("receive", json.dumps(renewed).encode())
        self.command("install")
        self.assertNotEqual((self.installed / "current").readlink(), previous)
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)

    def test_invalid_uploads_do_not_replace_valid_state(self):
        valid = self.bundle()
        self.command("receive", json.dumps(valid).encode())
        original = (self.staging / "bundle.json").read_bytes()
        mismatch = self.bundle()
        mismatch["key"] = valid["key"]
        for invalid in [
            mismatch,
            self.bundle("*.polpetta.online"),
            self.bundle("other.polpetta.online"),
            {"certificate": "not PEM", "key": "not PEM"},
            {**valid, "extra": "ignored?"},
        ]:
            self.command("receive", json.dumps(invalid).encode(), success=False)
            self.assertEqual((self.staging / "bundle.json").read_bytes(), original)
        self.command("receive", b"x" * 65537, success=False)
        self.command("receive", json.dumps(self.bundle(days=0)).encode(), success=False)

    def test_install_revalidates_staging_and_rejects_symlinks(self):
        self.command("install")  # Missing upload on first boot is harmless.
        (self.staging / "bundle.json").write_text(
            json.dumps(self.bundle("*.polpetta.online"))
        )
        self.command("install", success=False)
        (self.staging / "bundle.json").unlink()
        (self.staging / "bundle.json").symlink_to(self.ca)
        self.command("install", success=False)
        self.assertFalse((self.installed / "current").exists())
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
