"""Select a native direnv whitelist only for a boundary-checked .envrc.

The manual config remains available everywhere else. A symlink must not turn
an outside .envrc into an implicitly approved one.
"""

import os
import sys
from pathlib import Path

NIX_ROOT = Path("/workspace/nix")
CODE_ROOT = Path("/workspace/code")


def trusted(path):
    path = Path(path)
    try:
        actual = path.resolve(strict=True)
    except OSError:
        return False

    def allowed(value):
        return value.is_relative_to(NIX_ROOT) or (
            value.is_relative_to(CODE_ROOT) and value != CODE_ROOT
        )

    return allowed(path) and allowed(actual)


def config_scope(cwd):
    cwd = Path(cwd).absolute()
    for parent in [cwd, *cwd.parents]:
        envrc = parent / ".envrc"
        if envrc.exists() or envrc.is_symlink():
            return "trusted" if trusted(parent) and trusted(envrc) else "manual"
    return "manual"


if __name__ == "__main__":
    binary, configuration, *arguments = sys.argv[1:]
    cwd = Path.cwd()
    if arguments and arguments[0] == "exec" and len(arguments) > 1:
        cwd = Path(arguments[1]).absolute()
    os.environ["DIRENV_CONFIG"] = str(Path(configuration) / config_scope(cwd))
    os.execv(binary, [binary, *arguments])
