# T3 Code with Pi

T3 Code runs alongside OpenChamber at
`https://t3code.internal.polpetta.online`, accessible only through the tailnet.
Container ID 27 (`10.0.1.27:3000`) uses UID 5021/GID 5000, shared with
OpenChamber and workspace Syncthing. OpenChamber remains the fallback. Avoid
concurrent edits to the same Git working tree from both UIs.

T3 comes from the pinned `myPackages` input, Pi from nixpkgs. Pi is the only
installed harness in the new container. Initial chat and auxiliary generation
selections use Pi's default model, with **Full access** tool permissions.
These are seeded defaults, not choices reset on every restart.

## Deployment and first login

Deployment, secrets and privileged host operations are Billy's responsibility.
Build validation does not deploy anything:

```sh
nix build .#nixosConfigurations.serverone.config.system.build.toplevel
nix build .#checks.x86_64-linux.agent-containers \
  .#checks.x86_64-linux.server-policy .#checks.x86_64-linux.shell-syntax
```

After deployment, authenticate **inside t3code** as UID 5021, with
`HOME=/home/t3` and `PI_CODING_AGENT_DIR=/home/t3/.pi/agent`. Run `pi`, then
`/login`, open the authorization URL locally and follow the provider's URL/code
instructions. Select the model/thinking level through Pi/T3. Credentials and
old conversations from OpenCode are not imported.

For a real TTY, an administrator on serverone can use:

```sh
nerdctl exec -it --user 5021:5000 t3code /bin/pi
```

The restricted `exec-in-container` wrapper forwards stdin but has no TTY.
T3 uses native pairing rather than an OpenChamber password or development
auth token. Inside t3code, create a pairing link with:

```sh
t3 auth pairing create --base-dir /home/t3/.t3 \
  --base-url https://t3code.internal.polpetta.online
```

Treat the output as a password. `serve` also prints pairing details at startup,
so restrict access to serverone's journal. Paired sessions survive recreation;
use T3 connection settings/auth CLI to revoke them. No new provider callback
port is published. OpenChamber retains its loopback-only 1455 mapping. Determine
the chosen Pi provider's actual callback requirements before adding any mapping.

## Storage and isolation

- `/mnt/SSD/apps/t3code/home` mounts at `/home/t3`. T3 state lives in `.t3/`;
  Pi authentication, settings and native sessions in `.pi/agent/`.
- `/mnt/SSD/apps/t3code/tmp` mounts at `/tmp`, including scratch `/tmp/opencode`.
- `/mnt/SSD/apps/t3code/nix-root/nix` mounts at `/nix`, independent of
  OpenChamber's private store.
- `/mnt/SSD/apps/openchamber/workspaces` stays at `/workspace` in both
  containers. Existing Syncthing folders do not change.
- `/mnt/SSD/agent-config` mounts read-write at `/agent-config` in both
  containers. It contains only `AGENTS.md`, `skills/` and future repo metadata.
  Syncthing mounts the same directory at `/var/syncthing/Sync/agent-config`,
  with the same UID and without recursively changing its permissions.

The image root is read-only, capabilities are dropped and no-new-privileges
is enabled. Limits are 8 GiB RAM, four CPUs and 2048 PIDs. Nix sandboxing stays
deliberately disabled. Approval modes and project trust are not OS sandboxes.
No host daemon/runtime socket is mounted. Trusted agents can affect both
containers through shared files.

Chromium with fonts/container-compatible flags, nvim-fmt, Nix, nix-direnv,
Git/GitHub CLI, SSH and the existing agent utilities are available. Language
formatters still come from project devShells. The bot SSH secret is read-only
and rotation restarts both containers. The daily `t3code-nix-gc` timer uses
OpenChamber's non-destructive `nh clean user` policy, preserving live direnv
roots. Runtime/extensions are private-store seed roots. Do not wipe the store
to upgrade.

## Shared instruction/skill migration

`agent-config-migration.service` runs as UID 5021 before either agent container
and before Syncthing.
It seeds the host directory from the **live** OpenChamber global AGENTS.md
and `.config/opencode/skills`, `.agents/skills` and optional `.claude/skills`.
Symlink targets, including private-store resources, become portable copies.
Supporting files and instruction bytes are preserved; credentials are excluded.

Both harnesses then consume the same host content:

- Pi's `.pi/agent/AGENTS.md` links to `/agent-config/AGENTS.md`; its resource
  list loads `/agent-config/skills`.
- OpenCode's `.config/opencode/AGENTS.md` and `skills` link to those shared
  paths. Compatibility skill trees are moved outside discovery to avoid
  duplicates. Other OpenCode config, plugins and authentication stay in place.

Original files, SHA-256 inventory and the completion marker live outside the
shared directory in
`/mnt/SSD/apps/openchamber/home/.local/state/agent-config-migration/`.
`original/` is the non-discovered backup. Migration never overwrites later
edits. Duplicate names, conflicting host files and destination symlinks fail
instead of silently discarding content. Resolve conflicts before retrying.
Explicit custom roots/remote catalogs require separate inventory and migration.

The host directory has UID 5021/containers ownership and an inherited admin
ACL. Host edits and edits through either agent affect the same source.
Directory mounts keep atomic editor/future Syncthing replacements visible.
Send `/t3-reload` in an idle Pi thread to refresh resources. OpenCode retains
its own file watching and `/reload`; a Pi reload does not reload OpenCode.

The directory is available to Syncthing as `~/Sync/agent-config`. Add/share
that folder through Syncthing's UI when ready; the mount does not configure
synchronization or initialize a Git repository. Never sync `.pi`, `.t3`,
credentials, sessions or migration backups with
agent-config. Coordinate simultaneous edits and resolve sync conflicts before
loading changed skills.

## Declarative extensions and direnv

If the T3 home retains `.agents/skills` from an older trial, startup moves
overlapping skill copies to `.local/state/pi/legacy-skills/` and replaces
them with aliases to the shared skills. Pi deduplicates identical real paths,
so its automatic discovery no longer conflicts with the explicit shared
resource list. Original contents and unique user skills are preserved.
After deploying this fix, reopen existing Pi threads or use `/t3-reload`.

`services/pi/extensions/default.nix` pins reviewed sources/hashes. Local store
paths load without npm/Git downloads at startup. `setup.py` reconciles only
Nix-owned resource entries; custom extensions, model settings and credentials
remain writable. Installed extensions are:

- Workspace integration: direnv for agent bash and Pi `!`/`!!` commands, plus
  scoped Pi project trust.
- `@juicesharp/rpiv-ask-user-question`, including required `rpiv-config` but
  not the umbrella workflow/optional i18n extension. T3 uses sequential native
  RPC dialogs, textual multi-select and custom answers, not terminal tabs/notes.
- `pi-t3code-reload`: `/t3-reload` refreshes extensions, skills, context files,
  prompts, themes and settings without a model request or lost history. It
  refuses busy/queued/reentrant reloads. Restart the session if reload fails
  after runtime shutdown or hangs. Reload does not upgrade the Pi executable.
  Pi does not count a standalone RPC bash command as busy, so avoid reloading
  while such a command is running.

Update pinned sources/dependencies in Nix, check, rebuild and deploy. Recreate
the container to reconcile changed extension paths, then reload existing Pi
threads. Restart sessions after changing Pi itself. Do not use `pi update` to
replace the Nix-managed executable or put extension code in agent-config.

Direnv automatically approves `.envrc` contents in `/workspace/nix` and repo
descendants under `/workspace/code/`. A wrapper selects native whitelist config
only after canonical-path/boundary checks. Sibling-prefix paths,
`/workspace/code/.envrc` and symlink escapes retain manual approval. Changes
from Git pulls are trusted automatically in approved roots. Both scopes use
nix-direnv and strict environment evaluation, so failed setup does not fall
through into command execution. Pi separately auto-trusts project settings/extensions in those same
roots, without saving a blanket `always` policy; normal trust applies elsewhere.

Each Pi bash call runs `direnv exec` at its execution cwd. Changes/unsets stay
in the child process; native Pi streaming, cancellation and timeouts remain.
A blocked/failed `.envrc` prevents command execution. Project-cwd changes
between calls select the new environment. A `cd` **inside one command** does
not run an interactive prompt hook: use `direnv exec /path/to/project bash -c
'command'` explicitly. T3's interactive Bash loads direnv at each prompt.

## Compatibility and acceptance

Copied skills/instructions are intentionally unchanged:

- OpenChamber browser, rendering, notifications, knowledge, schedules and
  session tools do not become Pi tools. Chromium alone is not a browser tool.
- `define-plan` references subagents and questions. The requested extension
  supplies `ask_user_question`, but no Pi subagent extension is added.
- OpenCode/OpenChamber built-in skills and injected harness instructions are
  not files in the migrated trees and are not cloned. OpenCode skill policies
  are not translated into Pi policy.
- Shell-oriented skills retain searxng, read-nix-docs, agent-up, Byparr and
  Python/PDF utilities. Some still require npx, project dependencies, remote
  access or a running service.
- Global instructions retain original OpenCode wording/paths. `/tmp/opencode`
  remains available; the nix-store guard and other tool ports are deferred.

Monitoring uses `/.well-known/t3/environment`, not a nonexistent `/health`
that might return SPA HTML. The framework checks status, not the JSON body.
After deployment/authentication verify a real Pi thread, model discovery,
direnv commands, formatting, skills, both extension UIs, resume after restart,
shared edits, terminal integration, pairing and rejection of unauthenticated
protected operations before considering OpenChamber retirement.

Trial rollback means returning to OpenChamber, still using agent-config. This
does not undo shared edits. To undo a failed migration, stop both consumers
and restore OpenCode discovery paths from `original/`, retaining newer shared
files. Do not delete either home/store, agent-config or workspaces. Retirement
and storage-path renames remain separately authorized tasks.
