"""Keep recoverable passwords and Radicale's hashes in one atomic file."""

import fcntl
import os
import secrets
import tempfile
from pathlib import Path

import bcrypt
from cryptography.fernet import Fernet


class Credentials:
    def __init__(self, directory: Path, key: str):
        self.file = directory / "htpasswd"
        self.lock = directory / "credentials.lock"
        self.cipher = Fernet(key.encode("ascii"))
        self.lock.touch(mode=0o600)
        with self.lock.open() as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.file.touch(mode=0o600, exist_ok=True)

    def get(self, username: str, *, rotate: bool = False) -> str:
        with self.lock.open() as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            lines = self.file.read_text(encoding="ascii").splitlines()
            # Radicale ignores these comments. Keeping both representations in
            # one file means a reset cannot leave them out of sync.
            prefix = f"# {username}:"
            for index, line in enumerate(lines):
                if line.startswith(prefix):
                    password = self.cipher.decrypt(line[len(prefix) :].encode("ascii"))
                    if not rotate:
                        return password.decode("ascii")
                    lines.pop(index)
                    lines = [
                        line for line in lines if not line.startswith(f"{username}:")
                    ]
                    break

            password = secrets.token_urlsafe(32)
            encrypted = self.cipher.encrypt(password.encode("ascii")).decode("ascii")
            digest = bcrypt.hashpw(password.encode("ascii"), bcrypt.gensalt()).decode(
                "ascii"
            )
            lines.extend((prefix + encrypted, f"{username}:{digest}"))
            self._replace("\n".join(lines) + "\n")
            return password

    def _replace(self, content: str) -> None:
        fd, path = tempfile.mkstemp(dir=self.file.parent, prefix=".htpasswd-")
        try:
            with os.fdopen(fd, "w", encoding="ascii") as file:
                file.write(content)
                file.flush()
                os.fsync(file.fileno())
            os.replace(path, self.file)
            dir_fd = os.open(self.file.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        finally:
            Path(path).unlink(missing_ok=True)
