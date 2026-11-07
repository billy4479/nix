import { realpathSync } from "node:fs";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
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
    async exec(command, cwd, options) {
      const directory = await mkdtemp(join(tmpdir(), "pi-direnv-"));
      const log = join(directory, "setup.log");
      let failed = true;
      try {
        // Capture setup only. Restore the original streams and close the spare
        // descriptors before running the user's command in a fresh shell.
        const run = `exec ${quote(programs.bash)} --noprofile --norc -c ${quote(command)} 1>&3 2>&4 3>&- 4>&-`;
        const result = await local.exec(
          `exec ${quote(programs.direnv)} exec ${quote(cwd)} ${quote(programs.bash)} --noprofile --norc -c ${quote(run)} 3>&1 4>&2 >${quote(log)} 2>&1`,
          cwd,
          options,
        );
        failed = result.exitCode !== 0;
        return result;
      } finally {
        try {
          if (failed) {
            const output = await readFile(log).catch(() => Buffer.alloc(0));
            if (output.length) options.onData(output);
          }
        } finally {
          await rm(directory, { recursive: true, force: true });
        }
      }
    },
  };
}
