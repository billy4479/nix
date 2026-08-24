# OpenChamber Server

OpenChamber runs in the `openchamber` nerdctl container and is available
internally at `https://openchamber.internal.polpetta.online`. The container uses
UID 5021 and the shared containers GID 5000. OpenChamber starts and manages its
OpenCode backend inside the same container.

Clients can also connect directly over the tailnet at `10.0.1.21:3000`.
OpenChamber UI authentication remains mandatory because the application
provides shell access.

## OpenAI browser authentication

OpenAI fixes its OAuth callback to `http://localhost:1455/auth/callback`.
OpenCode listens for that callback inside the container, and nerdctl publishes
port 1455 only on `serverone`'s loopback interface. Before starting a new
browser authentication attempt, run this on the machine with the browser:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 1455:127.0.0.1:1455 serverone
```

Keep the SSH process running until authentication completes. Start a fresh
authentication attempt after opening the tunnel; callback URLs contain
single-use state and replaying an old URL fails CSRF validation. Stop the SSH
process afterward.

## Private Nix store

The container sees a conventional writable `/nix` backed by
`/mnt/SSD/apps/openchamber/nix-root/nix` on `serverone`. Before starting the
container, `nerdctl-openchamber.service` copies the declared runtime closures
into that store and registers GC roots for them. The image's `/nix` is then
hidden by the private store mount.

This lets OpenCode, direnv, and agent shell commands use normal `/nix/store`
paths without wrappers or access to the host Nix daemon. Do not recursively
change ownership under the private store manually. Startup makes it a
single-user store owned by the OpenChamber container UID so that Nix can add
paths and garbage-collect obsolete ones. Startup removes inherited host ACLs and
setgid bits from the store directories because group-writable build outputs are
rejected by Nix and unmapped host groups interfere with sandboxed builds.

The store is deliberately not synchronized. To garbage-collect it, run the GC
through the container so process roots and the container's filesystem view are
used:

```sh
nerdctl exec openchamber nix store gc
```

Build scratch space is persisted at `/mnt/SSD/apps/openchamber/tmp` instead of a
tmpfs so large Nix builds do not consume server memory.

After the first deployment, verify that containerd's seccomp policy permits
the unprivileged user and mount namespaces required by the Nix sandbox:

```sh
nerdctl exec openchamber nix build --no-link nixpkgs#hello
nerdctl exec openchamber nix shell nixpkgs#hello -c hello
```

Do not grant `--privileged` or broad host capabilities if sandbox creation
fails; adjust the runtime's namespace/seccomp policy narrowly instead.

## Workspaces

The SSD directory `/mnt/SSD/apps/openchamber/workspaces` is mounted at
`/workspace` in the OpenChamber container. Its `code` and `nix` subdirectories
are also mounted over Syncthing's existing paths:

- `/mnt/SSD/apps/openchamber/workspaces/code` at `/var/syncthing/Sync/code`.
- `/mnt/SSD/apps/openchamber/workspaces/nix` at `/var/syncthing/Sync/nix`.

Syncthing still sees `~/Sync/code` and `~/Sync/nix`, so its folder configuration
does not change. The nested mounts only change the physical storage backing
those paths. Syncthing and OpenChamber both run as UID 5021, so either service
can read, update, and change the mode of files created by the other. Their
containers and bind mounts remain separate: OpenChamber cannot see Syncthing's
configuration or its other synchronized folders. Syncthing runs without Linux
capabilities and with `no-new-privileges`. Do not enable the `ignorePerms`
folder option, that would stop executable bit synchronization.

On the first deployment after switching to the shared UID, Syncthing's volume
setup recursively changes its configuration, synchronized data, and workspace
ownership from UID 5002 to UID 5021. This can take some time on a large tree.
Because Git does not consider ACLs when checking repository ownership, the
container's system Git configuration marks all
repositories as safe. A global rule is necessary because Nix's libgit2 does not
support Git's `safe.directory` path globs. This exception is confined to the
dedicated development container. The existing HDD data must be copied to the
SSD before deploying this configuration. Build outputs, `.direnv`, dependency
directories, and other generated artifacts should normally be excluded with
Syncthing ignore patterns.

## Secrets

The `serverone` SOPS file must provide:

- `openchamber-env`, an environment file containing at least
  `OPENCHAMBER_UI_PASSWORD=...` and `OPENCODE_JWT_SECRET=...`.
- `openchamber-ssh-key`, a dedicated private SSH key for the agent identity.
- `public_keys/ssh/openchamber.pub`, the corresponding public key.

The public key is authorized for the unprivileged `billy` user on all four
managed hosts. Do not use a personal administrative key or forward a personal
SSH agent into the container.

The private key is mounted read-only at `/home/openchamber/.ssh/id_ed25519`.
OpenChamber's writable home, sessions, cache, and SSH host keys are persisted
under `/mnt/SSD/apps/openchamber/home`.

The same key belongs to the dedicated `billy4479-bot` GitHub account, which has
access to private flake inputs. GitHub's SSH host key is pinned in the container
image rather than accepted on first use.

The mounted SSH configuration provides `computerone`, `portatilo`, `serverone`,
and `vps-proxy` aliases. Agents can therefore connect with `ssh HOSTNAME`
without relying on Tailscale MagicDNS inside the container.

## Configuration

The `openchamber-web` package is overridden to use the same customized OpenCode
package as the Home Manager installations. The package, configuration, and
skills are assembled by
`../user/modules/applications/editor/opencode/artifacts.nix`, however the
configuration, skills and AGENTS.md are kept non-declarative. What is built in
`artifacts.nix` is just a reference.
