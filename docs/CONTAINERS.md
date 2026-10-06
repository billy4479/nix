# Container IPs

Container IPs are derived from their container IDs using the formula: `10.0.1.${id}`

Containers with a DNS entry have ids from 2 to 127, other non-public facing containers have ids from 128 to 255.

## Creating a new container

To create containers use the nix module at `../containers/module.nix`.
Prefer building an image from nix packages rather then pulling one.

If you decide to pull an image you should add it to `../containers/images` and update `../containers/images.nix` using
```sh
nix-prefetch-docker --os linux --arch amd64 --image-tag TAG --image-name IMAGE_URL
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

## Seccomp

By default nerdctl applies containerd's default seccomp profile, which blocks
`clone`/`unshare` with namespace flags and the mount syscalls. Containers that
need to create their own namespaces (for example the Nix sandbox in
openchamber) can set `seccompProfile` to a JSON profile:

```nix
seccompProfile = ./seccomp-profile.json;
```

The module passes it as `--security-opt seccomp=<path>`. A seccomp profile
only gates which syscalls may be issued; the kernel still enforces capability
checks. Allowing namespace and mount syscalls therefore lets an unprivileged
container do only what any local user may already do (create user namespaces
and mount inside them), without granting any capability. Vendor the profile by
generating it from containerd's own `contrib/seccomp` Go source (matching the
containerd version on the host) and adding the needed syscalls; see
`containers/openchamber/seccomp-profile.json` for the current example.
Containers with a `seccompProfile` stay exec-able through exec-in-container:
unlike capabilities, a profile is part of the reviewed policy rather than a
privilege grant.

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

## tmpfs

`/tmp` is mounted as a tmpfs capped at 128MB by default. tmpfs lives in RAM and
counts towards the container's memory usage, and some applications never clean
up their own temporary files (jackett's self-updater once accumulated >1GB of
downloaded release archives this way). Raise the cap per-container when an
application legitimately needs more scratch space:

```nix
tmpfs = [ "/tmp:size=512m" ];
```

Current overrides: byparr (1g), jellyfin (1g), nginx (2g), stirling-pdf (512m).
openchamber opts out entirely with `tmpfs = [ ];`.

nginx needs the extra space because it buffers large proxied transfers to
`proxy_temp_path` under `/tmp`: with the 128MB default, any buffered response
or upload bigger than 128MB hit ENOSPC and the transfer aborted mid-stream.

## Startup Dependencies

Container ordering is controlled by the `dependsOn`, `dns`, and `useNginx` options in `../containers/module.nix`.

Use `dependsOn = [ "other-container" ];` for explicit application dependencies. This generates systemd ordering and requirement dependencies on `nerdctl-other-container.service`.

Containers using the default bind9 DNS server automatically start after `bind9`. This applies when `dns` points to the bind9 container IP. Set `dns = null;` only for containers that should not use container DNS.

Set `useNginx = true;` for containers served through the nginx reverse proxy. These containers automatically start after `nginx`. Since nginx uses bind9 DNS, this also places them after bind9.

`headscale` is intentionally prioritized after the public entrypoint stack. The effective base ordering is:
```text
bind9 -> nginx -> headscale -> other containers
```

All containers except `bind9`, `nginx`, and `headscale` automatically start after `headscale` when it exists. This keeps headscale available before the rest of the application stack starts.

Current media stack ordering:
```text
byparr -> jackett -> sonarr/radarr
qbittorrent -> sonarr/radarr
```

## Container Mapping

Always keep this table in sync when adding new containers.

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
| Stirling PDF | 12 | 10.0.1.12 |
| mc-runner | 13 | 10.0.1.13 |
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
| Immich (ML) | 128 | 10.0.1.128 |
| Immich (valkey) | 129 | 10.0.1.129 |
| Immich (DB) | 130 | 10.0.1.130 |
| frp | 131 | 10.0.1.131 |
| Certbot | 132 | 10.0.1.132 |
| Byparr | 134 | 10.0.1.134 |
