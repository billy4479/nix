"""Seed portable shared agent files, then redirect OpenCode's discovery paths.

Run as the agent UID on the host, before either container starts. Never copy
credentials or modify the source instruction/skill contents.
"""

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path


def present(path):
    return path.exists() or path.is_symlink()


def resolve_source(path, home, store, seen=None):
    """Resolve container-absolute links against the original mounted home/store."""
    seen = set() if seen is None else seen
    path = Path(path)
    # Resolve each component, since a directory may itself be a symlink.
    for parent in reversed([path, *path.parents]):
        if parent.is_symlink():
            if parent in seen:
                raise ValueError(f"Symlink cycle: {parent}")
            target = Path(os.readlink(parent))
            if target.is_absolute():
                if target.is_relative_to("/home/openchamber"):
                    target = home / target.relative_to("/home/openchamber")
                elif target.is_relative_to("/nix/store"):
                    target = store / target.relative_to("/nix/store")
            else:
                target = parent.parent / target
            return resolve_source(
                target / path.relative_to(parent), home, store, seen | {parent}
            )
    return path


def snapshot(path, destination, home, store, ancestors=None):
    path = resolve_source(path, home, store)
    ancestors = set() if ancestors is None else ancestors
    if path in ancestors:
        raise ValueError(f"Directory cycle: {path}")
    if path.is_dir():
        destination.mkdir()
        for child in sorted(path.iterdir()):
            snapshot(child, destination / child.name, home, store, ancestors | {path})
    elif path.is_file():
        shutil.copyfile(path, destination)
        destination.chmod(0o770 if os.access(path, os.X_OK) else 0o660)
    else:
        raise ValueError(f"Missing or unsupported skill resource: {path}")


def inventory(root):
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def redirect(path, target, backup):
    if path.is_symlink() and os.readlink(path) == target:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if present(path):
        backup.parent.mkdir(parents=True, exist_ok=True)
        if present(backup):
            raise ValueError(
                f"Both original and migration backup exist: {path}, {backup}"
            )
        path.rename(backup)
    path.symlink_to(target)


def migrate(home, destination, state, store):
    if destination.is_symlink():
        raise ValueError(f"Shared directory must not be a symlink: {destination}")
    state.mkdir(parents=True, exist_ok=True)
    destination.mkdir(parents=True, exist_ok=True)
    with (state / "migration.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        marker = state / "seed.json"
        if not marker.exists():
            with tempfile.TemporaryDirectory(prefix="seed-", dir=state) as temporary:
                staged = Path(temporary)
                snapshot(
                    home / ".config/opencode/AGENTS.md",
                    staged / "AGENTS.md",
                    home,
                    store,
                )
                (staged / "skills").mkdir()
                for source in [
                    home / ".config/opencode/skills",
                    home / ".agents/skills",
                    home / ".claude/skills",
                ]:
                    source = resolve_source(source, home, store)
                    if not source.exists():
                        continue
                    for skill in sorted(source.iterdir()):
                        target = staged / "skills" / skill.name
                        if present(target):
                            raise ValueError(f"Duplicate skill name: {skill.name}")
                        snapshot(skill, target, home, store)
                manifest = inventory(staged)
                if not any(name.endswith("/SKILL.md") for name in manifest):
                    raise ValueError(
                        "No skills found; refusing an incomplete migration"
                    )
                # Preflight the entire copy before touching existing host content.
                for name, digest in manifest.items():
                    target = destination / name
                    if target.is_symlink():
                        raise ValueError(
                            f"Host destination must be self-contained: {target}"
                        )
                    if present(target) and (
                        not target.is_file()
                        or hashlib.sha256(target.read_bytes()).hexdigest() != digest
                    ):
                        raise ValueError(
                            f"Host content conflicts with migration source: {target}"
                        )
                    for parent in target.parents:
                        if parent == destination:
                            break
                        if present(parent) and (
                            parent.is_symlink() or not parent.is_dir()
                        ):
                            raise ValueError(f"Unsafe destination directory: {parent}")
                for name in manifest:
                    target = destination / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if not present(target):
                        # Publish a complete file exclusively, so interruption
                        # cannot leave a half-written destination on retry.
                        with tempfile.NamedTemporaryFile(
                            dir=target.parent, delete=False
                        ) as output:
                            temporary_file = Path(output.name)
                            output.write((staged / name).read_bytes())
                        try:
                            temporary_file.chmod((staged / name).stat().st_mode & 0o777)
                            os.link(temporary_file, target)
                        finally:
                            temporary_file.unlink()
                for name, digest in manifest.items():
                    if (
                        hashlib.sha256((destination / name).read_bytes()).hexdigest()
                        != digest
                    ):
                        raise ValueError(f"Copy verification failed: {name}")
                pending = state / "seed.json.tmp"
                pending.write_text(json.dumps(manifest, indent=2) + "\n")
                pending.replace(marker)
        if (
            not (destination / "AGENTS.md").is_file()
            or not (destination / "skills").is_dir()
        ):
            raise ValueError(
                "Shared agent configuration is missing; refusing to reseed over edits"
            )
        backup = state / "original"
        redirect(
            home / ".config/opencode/AGENTS.md",
            "/agent-config/AGENTS.md",
            backup / "AGENTS.md",
        )
        redirect(
            home / ".config/opencode/skills",
            "/agent-config/skills",
            backup / "opencode-skills",
        )
        # Empty this second discovery root by retaining it outside discovery.
        # A single shared root avoids loading every skill twice.
        for directory in ["agents", "claude"]:
            old = home / f".{directory}/skills"
            if present(old):
                saved = backup / f"{directory}-skills"
                if present(saved):
                    raise ValueError(
                        f"Unexpected second skill tree after migration: {old}"
                    )
                old.rename(saved)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--store", type=Path, required=True)
    args = parser.parse_args()
    migrate(args.home, args.destination, args.state, args.store)
