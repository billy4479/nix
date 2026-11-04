"""Bounded, atomic certificate transfer without a remote shell or file extraction."""

import argparse
import grp
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_BUNDLE_SIZE = 65536


def read_bundle(stream):
    data = stream.read(MAX_BUNDLE_SIZE + 1)
    if len(data) > MAX_BUNDLE_SIZE:
        raise ValueError("certificate bundle exceeds 64 KiB")
    bundle = json.loads(data)
    if not isinstance(bundle, dict) or set(bundle) != {"certificate", "key"}:
        raise ValueError("expected exactly certificate and key")
    if not all(isinstance(value, str) and value for value in bundle.values()):
        raise ValueError("empty or invalid PEM data")
    return bundle


def openssl(*args):
    # Never include PEM contents or OpenSSL diagnostics in the service journal.
    return subprocess.check_output(["openssl", *args], stderr=subprocess.DEVNULL)


def validate(bundle, hostname, ca_file):
    with tempfile.TemporaryDirectory() as directory:
        certificate = Path(directory) / "certificate.pem"
        key = Path(directory) / "key.pem"
        certificate.write_text(bundle["certificate"])
        key.write_text(bundle["key"])
        san = openssl(
            "x509", "-in", str(certificate), "-noout", "-ext", "subjectAltName"
        )
        # This transfer must never carry the web wildcard key again.
        if san.decode().splitlines()[1:] != [f"    DNS:{hostname}"]:
            raise ValueError("certificate must contain only the DERP DNS name")
        openssl("x509", "-in", str(certificate), "-noout", "-checkend", "86400")
        openssl(
            "verify",
            "-CAfile",
            ca_file,
            "-untrusted",
            str(certificate),
            str(certificate),
        )
        cert_public = openssl("x509", "-in", str(certificate), "-noout", "-pubkey")
        key_public = openssl("pkey", "-in", str(key), "-pubout")
        if cert_public != key_public:
            raise ValueError("certificate and key do not match")


def staged_bundle(staging):
    # The upload account owns this directory: never follow one of its symlinks.
    fd = os.open(staging / "bundle.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("staged bundle is not a regular file")
        return read_bundle(stream)


def receive(args):
    bundle = read_bundle(sys.stdin.buffer)
    validate(bundle, args.hostname, args.ca_file)
    staging = Path(args.staging_dir)
    try:
        if staged_bundle(staging) == bundle:
            return
    except FileNotFoundError:
        pass
    fd, temporary = tempfile.mkstemp(prefix=".incoming-", dir=staging)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(bundle, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, staging / "bundle.json")
    finally:
        Path(temporary).unlink(missing_ok=True)


def install(args):
    try:
        bundle = staged_bundle(Path(args.staging_dir))
    except FileNotFoundError:
        return  # First boot: wait for the first upload, not an old wildcard.
    validate(bundle, args.hostname, args.ca_file)
    destination = Path(args.install_dir)
    digest = hashlib.sha256(json.dumps(bundle, sort_keys=True).encode()).hexdigest()
    current = destination / "current"
    restart_requested = destination / "restart-requested"
    if (
        current.is_symlink()
        and current.readlink() == Path(digest)
        and restart_requested.exists()
        and restart_requested.read_text() == digest
    ):
        return
    gid = grp.getgrnam(args.group).gr_gid
    version = destination / digest
    if not version.exists():
        # Both files are complete before one atomic symlink switch publishes them.
        temporary_version = Path(tempfile.mkdtemp(prefix=".install-", dir=destination))
        try:
            temporary_version.chmod(0o750)
            os.chown(temporary_version, -1, gid)
            for field, extension in [("certificate", "crt"), ("key", "key")]:
                path = temporary_version / f"{args.hostname}.{extension}"
                path.write_text(bundle[field])
                path.chmod(0o640)
                os.chown(path, -1, gid)
            temporary_version.rename(version)
        finally:
            if temporary_version.exists():
                shutil.rmtree(temporary_version)
    temporary = destination / ".current-new"
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(digest)
    temporary.replace(current)
    # The relay is ordered after this oneshot. Waiting here deadlocks startup.
    subprocess.run(
        ["systemctl", "--no-block", "try-restart", "derper-derp.service"], check=True
    )
    # A failed D-Bus request must remain retryable even after publication. A
    # partial marker after a crash is also harmless: the next run retries.
    restart_requested.write_text(digest)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    send = commands.add_parser("send")
    send.add_argument("certificate")
    send.add_argument("key")
    for command in ["receive", "install"]:
        command_parser = commands.add_parser(command)
        command_parser.add_argument("--staging-dir", required=True)
        command_parser.add_argument("--hostname", required=True)
        command_parser.add_argument("--ca-file", required=True)
        if command == "install":
            command_parser.add_argument("--install-dir", required=True)
            command_parser.add_argument("--group", required=True)
    args = parser.parse_args()
    try:
        if args.command == "send":
            json.dump(
                {
                    "certificate": Path(args.certificate).read_text(),
                    "key": Path(args.key).read_text(),
                },
                sys.stdout,
            )
        elif args.command == "receive":
            receive(args)
        else:
            install(args)
    except (OSError, ValueError, subprocess.CalledProcessError):
        print(
            "DERP certificate transfer failed validation or installation",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
