# Container IPs

Container IPs are derived from their container IDs using the formula: `10.0.1.${id}`

Containers with a DNS entry have ids from 2 to 127, other non-public facing containers have ids from 128 to 255.

## Creating a new container

User-facing services are defined through the `polpetta.services` API — see
`SERVICES.md`. One service file under `../services/services/` declares the
container plus how it is exposed (domain, access tier, raw ports).

The containers under `../containers/` are infrastructure only (the engine,
nginx, certbot) and set `nerdctl-containers` directly.

Provide a `copyToRoot` list and a nonempty `entrypoint` list. The module builds
an image with `pkgs.nix-snapshotter.buildImage`, automatically using the container
name and the `nix-local` tag. `copyToRoot` defaults to `[]` and adds to the shared
base described below. Executables referenced by Nix store paths in `entrypoint`
are included in the image closure without needing to copy them into `/bin`.

Images are loaded locally and run with `--snapshotter nix --pull never`.
There is no upstream Docker image pull or prefetch machinery.

For example:

```nix
copyToRoot = [
  (pkgs.certbot.withPlugins (plugins: [ plugins.certbot-dns-cloudflare ]))
];
entrypoint = [ "/bin/sh" ];
cmd = [ "-c" "trap : TERM INT; sleep infinity & wait" ];
```

`entrypoint` contains the application executable and any fixed arguments or
wrapper script. The module always prepends `tini --` to reap orphaned children
and forward signals; do not add Tini yourself. Use `cmd` for runtime arguments
and `environment` for runtime environment variables; no environment settings
belong in the image. Volumes, working directory, and other runtime options
remain separate.

### Shared image base

Every image includes:

- `dockerTools.binSh` (`/bin/sh`)
- `dockerTools.caCertificates` (the CA trust store)
- `coreutils` and `tini`
- `/etc/passwd` and `/etc/group`, with root, the configured container user
  (its `uid` and GID 5000), and nobody/nogroup
- `/etc/nsswitch.conf`, using files for users/groups and files/DNS for hosts

`userName` defaults to `environment.USER`, or `container-<uid>` when unset.
Set it explicitly for applications requiring a specific account name (Bind9
uses `bind`, PostgreSQL uses `postgres`). The passwd home and shell follow
`environment.HOME` and `environment.SHELL`, defaulting to `/var/empty` and
`/bin/sh`. These names do not change the numeric UID/GID used by nerdctl.

The module merges the base and `copyToRoot` into one filesystem tree. Explicit
application packages take precedence over defaults, so richer runtimes can
provide Bash and their own command variants without duplicate-path failures.

Generated images can be built individually with:

```sh
nix build .#nixosConfigurations.serverone.config.system.build.containerImages.certbot
```

## Process privileges

The container module drops every Linux capability and sets
`no-new-privileges` by default. Add only capabilities required by the service:

```nix
capabilities = [ "CAP_NET_BIND_SERVICE" ];
```

Currently only nginx and bind9 need that capability to listen on ports below
1024. Bind9 starts directly as its configured container UID rather than
starting as root and changing users. Do not put capability or security flags in
`extraOptions`; use the module options so the effective policy remains
declarative and can be validated.

## Resource limits

Set per-container CPU and memory limits with the module options:

```nix
memory = "8g"; # hard limit, passed to nerdctl --memory
cpus = 4;      # fraction of total CPU time, passed to nerdctl --cpus
```

`memory` is enforced by the kernel: processes exceeding it are OOM killed, and
tmpfs mounts (see below) count towards it. `cpus` throttles rather than
reserves: the container cannot use more than that share, but idle capacity
stays available to the rest of the system. Currently only openchamber (8g / 4
cpus) sets these.

## Start and stop timeouts

The unit's start job includes `preStart`, so volume permission fixes, private
Nix store seeding, and image loading all count against systemd's default 90s
start timeout. A preStart that legitimately moves a lot of data (e.g. openchamber
copying a fresh runtime closure into its private store after a deploy) should
raise it:

```nix
startTimeout = 600; # seconds; null keeps the 90s default
```

`stopTimeout` (also in seconds) tunes how long nerdctl waits before killing the
container on stop. Keep preStart cheap regardless: probe before repairing, and
skip work when nothing changed.

## tmpfs

`/tmp` is mounted as a tmpfs capped at 128MB by default. tmpfs lives in RAM and
counts towards the container's memory usage, and some applications never clean
up their own temporary files (jackett's self-updater once accumulated >1GB of
downloaded release archives this way). Raise the cap per-container when an
application legitimately needs more scratch space:

```nix
tmpfs = [ "/tmp:size=512m" ];
```

Current overrides: byparr (1g), jellyfin (1g), nginx (2g).
openchamber opts out entirely with `tmpfs = [ ];`.

nginx needs the extra space because it buffers large proxied transfers to
`proxy_temp_path` under `/tmp`: with the 128MB default, any buffered response
or upload bigger than 128MB hit ENOSPC and the transfer aborted mid-stream.

## Inspecting the nginx config

The complete nginx runtime config as deployed (hand-written infrastructure
plus the generated per-service vhosts) builds as a package, validated with
`nginx -t` against a throwaway certificate:

```sh
nix build .#nginx-config
cat result/nginx.conf result/vhosts.conf
```

## Private Nix store maintenance

OpenChamber runs `nh clean user` daily, inside its own container as its normal
UID, with no privilege elevation:

```sh
nh clean user --elevation-strategy none --keep 5 --keep-since 7d --keep-one --max 107374182400
```

This removes orphaned root registrations and ages out build-result roots older
than seven days, retaining at least five profile generations and any generations
younger than seven days. With the pinned nh version, `--keep-one` preserves all
live direnv roots. The container runtime seed roots are not age-cleanup targets.
Expired result-root registrations can be removed even while their `result`
symlink remains on disk; that output may then become collectable.

The module automatically copies and roots the complete merged image filesystem
in each private Nix store, in addition to `privateNixStore.seedPackages`.
This preserves the shared shell, CA store, coreutils, Tini, identity files, and
application root files when the private `/nix` mount hides the host store.

The subsequent GC preserves remaining roots and active build locks, attempting
to free up to 100 GiB per run. This is not a hard store-size cap. The job is
skipped when the container is inactive. Host nh/GC operates on a different store
and cannot clean this private one. ZFS snapshots can retain blocks after GC, so
pool usage and snapshot retention still matter.

Automatic full-store wiping is disabled for OpenChamber. The generic
`privateNixStore.wipeAboveGib` option remains an explicit destructive opt-in,
with a tested threshold and fail-closed input validation. It restores only seed
closures, not arbitrary user-rooted environments. Never enable it as a routine
way to recover disk space on a live development container.

## Startup Dependencies

Container ordering is controlled by the `dependsOn`, `dns`, and `useNginx` options in `../containers/module.nix`.

Use `dependsOn = [ "other-container" ];` for explicit application dependencies. This generates systemd ordering and requirement dependencies on `nerdctl-other-container.service`.

Containers using the default bind9 DNS server automatically start after `bind9`. This applies when `dns` points to the bind9 container IP. Set `dns = null;` only for containers that should not use container DNS.

Declaring a `web` endpoint on a service automatically sets `useNginx` on its container; these containers automatically start after `nginx`.

`headscale` is intentionally prioritized after the public entrypoint stack. The effective base ordering is:
```text
bind9 -> nginx -> headscale -> other containers
```

All containers except `bind9`, `nginx`, and `headscale` automatically start after `headscale` when it exists. This keeps headscale available before the rest of the application stack starts.

Current media stack ordering:
```text
byparr -> jackett -> sonarr/radarr
byparr -> mircrewrr -> sonarr/radarr
qbittorrent -> sonarr/radarr
```

## Container Mapping

Always keep this table in sync when adding new containers.

The shared PostgreSQL container is initialized and migrated according to
[`deployments/postgresql-migration.md`](./deployments/postgresql-migration.md).

| Container | ID | IP Address |
|-----------|----|----|
| Syncthing | 2 | 10.0.1.2 |
| Immich (Server) | 3 | 10.0.1.3 |
| Calendar Proxy | 4 | 10.0.1.4 |
| qBittorrent | 5 | 10.0.1.5 |
| nginx | 6 | 10.0.1.6 |
| radarr | 7 | 10.0.1.7 |
| jackett | 8 | 10.0.1.8 |
| sonarr | 9 | 10.0.1.9 |
| jellyfin | 10 | 10.0.1.10 |
| bind9 (DNS) | 11 | 10.0.1.11 |
| BentoPDF | 12 | 10.0.1.12 |
| game-server-runner | 13 | 10.0.1.13 |
| opencloud | 14 | 10.0.1.14 |
| headscale | 15 | 10.0.1.15 |
| headplane | 16 | 10.0.1.16 |
| ff | 17 | 10.0.1.17 |
| giuoco-del-divertimento | 18 | 10.0.1.18 |
| SearXNG | 19 | 10.0.1.19 |
| Luna Multiplayer | 20 | 10.0.1.20 |
| OpenChamber | 21 | 10.0.1.21 |
| AgentUp | 22 | 10.0.1.22 |
| Grafana | 23 | 10.0.1.23 |
| Outline | 24 | 10.0.1.24 |
| tsidp | 25 | 10.0.1.25 |
| Quote Bot | 26 | 10.0.1.26 |
| Immich (ML) | 128 | 10.0.1.128 |
| Immich (valkey) | 129 | 10.0.1.129 |
| PostgreSQL | 130 | 10.0.1.130 |
| Retired frp (reserved during edge migration) | 131 | 10.0.1.131 |
| Certbot | 132 | 10.0.1.132 |
| Outline (valkey) | 133 | 10.0.1.133 |
| Byparr | 134 | 10.0.1.134 |
| mircrewrr | 135 | 10.0.1.135 |
