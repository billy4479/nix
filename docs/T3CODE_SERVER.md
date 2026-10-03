# T3 Code Server

T3 Code runs in the `t3code` nerdctl container and is available internally at
`https://t3code.internal.polpetta.online`. The container uses the openchamber
UID 5021 and the shared containers GID 5000, and it shares the openchamber
workspaces. T3 Code starts and controls its provider agents (OpenCode, Claude
Code, Codex) inside the same container. Tini runs as PID 1 to forward signals
and reap orphaned child processes.

Clients can also connect directly over the tailnet at `10.0.1.24:3000`.

## Authentication

T3 Code has no password. Access is granted through pairing: a one-time
pairing URL or QR code (printed by the server on startup, or `t3 pair` inside
the container) authorizes a device, which then keeps a session. Treat pairing
URLs and authorization codes as passwords. Devices and sessions can be
revoked from the web UI's connection settings or with `t3 auth`.

## Providers

The container runtime provides the provider CLIs on `PATH`:

- `opencode` is the customized build from
  `user/modules/applications/editor/opencode/artifacts.nix`; it, `claude` and
  `codex` (both from nixpkgs) are on the container's `PATH`, which is where
  t3 discovers provider CLIs.
- `claude` and `codex` come from nixpkgs (`claude-code`, `codex`).

On the first container start, the non-declarative OpenCode state
(configuration, skills, authentication) is copied once from the openchamber
container's home at `/mnt/SSD/apps/openchamber/home` into
`/mnt/SSD/apps/t3code/home`. Afterwards the two homes develop independently.
Run `claude auth login` and `codex login` inside the container once to
authenticate the other providers:

```sh
ssh serverone sudo /run/current-system/sw/bin/exec-in-container t3code claude auth login
ssh serverone sudo /run/current-system/sw/bin/exec-in-container t3code codex login
```

Note that the `exec-in-container` wrapper does not allocate a TTY; interactive
logins may need `nerdctl exec -it` from serverone instead (requires root on
serverone).

## Private Nix store

The container sees a conventional writable `/nix` backed by
`/mnt/SSD/apps/t3code/nix-root` on `serverone`, seeded and rooted exactly like
the openchamber container's store. See OPENCHAMBER_SERVER.md for the store's
operational details; they apply verbatim. To garbage-collect it, run the GC
through the container:

```sh
ssh serverone sudo /run/current-system/sw/bin/exec-in-container t3code nix store gc
```

## Workspaces

The openchamber workspaces at `/mnt/SSD/apps/openchamber/workspaces` are
mounted at `/workspace` in the t3code container. Both containers and
Syncthing run as UID 5021, so all three can read and write the same
repositories while openchamber remains deployed as the fallback control
surface. Because Git does not consider ACLs when checking repository
ownership, the container's system Git configuration marks all repositories as
safe, mirroring the openchamber container.

## Secrets

The `serverone` SOPS file already provides `openchamber-ssh-key`, which the
t3code container mounts read-only at `/home/t3/.ssh/id_ed25519`. The key
belongs to the dedicated `billy4479-bot` GitHub account and is authorized for
the unprivileged `billy` user on all four managed hosts. Both the openchamber
and t3code containers restart when the key rotates. The SSH configuration
provides the `computerone`, `portatilo`, `serverone`, and `vps-proxy`
aliases, so agents can connect with `ssh HOSTNAME`.

No UI password secret is required: T3 Code authenticates devices through
pairing instead.

## Updating

Bump `version` and the two output hashes in the `t3code` package in the
nix-packages repository (commit message `t3code: update to X.Y.Z`), update
this flake's `myPackages` lock, and rebuild serverone. The container image is
rebuilt and reloaded automatically when its inputs change.

## Decommissioning openchamber

Once t3code has proven itself: remove the openchamber container import from
`system/hosts/serverone/containers.nix`, the `openchamber` nginx map entry,
its monitoring entry, and the now t3code-owned sops secrets
(`openchamber-env`; move `openchamber-ssh-key` ownership into
`containers/t3code`). The workspaces and their Syncthing mounts stay where
they are; a later rename of `/mnt/SSD/apps/openchamber/workspaces` would also
touch the Syncthing folder configuration and is best done as its own change.
