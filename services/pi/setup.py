"""Reconcile Nix-owned Pi resources; seed T3 defaults without resetting choices."""

import argparse
import json
import os
import tempfile
from pathlib import Path


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        json.dump(data, output, indent=2)
        output.write("\n")
    os.replace(temporary, path)


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def setup(home, extensions, shared=Path("/agent-config")):
    agent = home / ".pi/agent"
    agent.mkdir(parents=True, exist_ok=True)
    instructions = agent / "AGENTS.md"
    target = str(shared / "AGENTS.md")
    if instructions.is_symlink():
        if os.readlink(instructions) != target:
            raise ValueError(f"Unexpected instructions symlink: {instructions}")
    elif instructions.exists():
        raise ValueError(f"Refusing to overwrite existing instructions: {instructions}")
    else:
        instructions.symlink_to(target)
    settings_file = agent / "settings.json"
    settings = read_json(settings_file)
    owned_file = agent / ".nix-resources.json"
    previous = read_json(owned_file)
    resources = {
        "extensions": [
            str(extensions / name / "index.ts")
            for name in [
                "workspace",
                "rpiv-ask-user-question",
                "t3code-reload",
            ]
        ],
        "skills": [str(shared / "skills")],
    }
    for key, entries in resources.items():
        existing = settings.get(key, [])
        if not isinstance(existing, list):
            raise TypeError(f"{key} must be an array in {settings_file}")
        settings[key] = [
            entry
            for entry in existing
            if entry not in previous.get(key, []) and entry not in entries
        ] + entries
    # Journal ownership before publishing settings so an interrupted upgrade
    # still removes both the previous and the new managed paths on retry.
    write_json(
        owned_file,
        {
            key: list(dict.fromkeys(previous.get(key, []) + entries))
            for key, entries in resources.items()
        },
    )
    write_json(settings_file, settings)
    write_json(owned_file, resources)
    # T3 owns this mutable file after the initial seed. Defaults are not policy.
    t3 = home / ".t3/userdata/settings.json"
    if not t3.exists():
        selection = {"instanceId": "pi", "model": "default"}
        write_json(
            t3,
            {
                "providerInstances": {
                    "pi": {
                        "driver": "pi",
                        "enabled": True,
                        "config": {"binaryPath": "/bin/pi"},
                    },
                    "codex": {"driver": "codex", "enabled": False, "config": {}},
                    "claudeAgent": {
                        "driver": "claudeAgent",
                        "enabled": False,
                        "config": {},
                    },
                },
                "defaultModelSelection": selection,
                "textGenerationModelSelection": selection,
                "defaultRuntimeMode": "full-access",
                "addProjectBaseDirectory": "/workspace",
            },
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--extensions", type=Path, required=True)
    args = parser.parse_args()
    setup(args.home, args.extensions)
