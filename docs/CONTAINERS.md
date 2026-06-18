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
| Immich (ML) | 128 | 10.0.1.128 |
| Immich (valkey) | 129 | 10.0.1.129 |
| Immich (DB) | 130 | 10.0.1.130 |
| frp | 131 | 10.0.1.131 |
| Certbot | 132 | 10.0.1.132 |
| Byparr | 134 | 10.0.1.134 |
