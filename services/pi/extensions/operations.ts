import { realpathSync } from "node:fs";
import { sep } from "node:path";
import type { BashOperations } from "@earendil-works/pi-coding-agent";

export function trustedWorkspace(
  cwd: string,
  roots = {
    nix: "/workspace/nix",
    code: "/workspace/code",
  },
): boolean {
  try {
    const actual = realpathSync(cwd);
    // Check lexical boundaries AND canonical roots: do not trust symlink escapes.
    const inRoot = (root: string, includeRoot: boolean) => {
      if (!(cwd.startsWith(root + sep) || (includeRoot && cwd === root)))
        return false;
      return actual.startsWith(root + sep) || (includeRoot && actual === root);
    };
    return inRoot(roots.nix, true) || inRoot(roots.code, false);
  } catch {
    return false;
  }
}

const quote = (value: string) => "'" + value.replaceAll("'", "'\\''") + "'";

// Keep Pi's native execution backend responsible for streaming, process-tree
// cancellation, timeout, and session environment metadata. direnv applies its
// environment only to the child, including unsets, and refuses blocked .envrcs.
export function withDirenv(
  local: BashOperations,
  programs = {
    direnv: "/bin/direnv",
    bash: "/bin/bash",
  },
): BashOperations {
  return {
    ...local,
    exec(command, cwd, options) {
      return local.exec(
        `exec ${quote(programs.direnv)} exec ${quote(cwd)} ${quote(programs.bash)} --noprofile --norc -c ${quote(command)}`,
        cwd,
        options,
      );
    },
  };
}
