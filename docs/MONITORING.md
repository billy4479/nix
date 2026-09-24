# Monitoring (serverone)

serverone runs a small, native NixOS monitoring stack: Prometheus scrapes a
bunch of local exporters plus every service container, Alertmanager routes
alerts to the shared Telegram bot, and Grafana (the only containerized
piece) provides the dashboards at
[grafana.internal.polpetta.online](https://grafana.internal.polpetta.online).

Everything lives in two places:

- `system/hosts/serverone/monitoring.nix` — Prometheus, exporters,
  Alertmanager, alert rules and the zpool textfile exporter.
- `containers/grafana/` — the Grafana container, its provisioning files and
  the two dashboards.

## Architecture

```text
                       ┌────────────────────────── serverone (host) ──────────────────────────┐
                       │                                                                      │
 node_exporter :9100 ──┤┐                                                                     │
 smartctl_exporter :9633 │  Prometheus :9090 ── alerts ──> Alertmanager :9093 ──> Telegram bot │
 zfs_exporter :9134 ────┤│                    │                                               │
 nginx-exporter :9113 ──┤┘                    │                                               │
 cAdvisor :8080 ────────┤                     │ scrape                                        │
 blackbox :9115 ────────┤<────────────────────┘                                               │
 zpool textfile ────────┘                                                                     │
                       │   nerdctl bridge (10.0.1.0/24)                                       │
                       │   nginx :8082 /stub_status    all service containers (http/tcp)      │
                       └──────────────────────────────────────────────────────────────────────┘
```

Prometheus keeps 90 days of samples (`services.prometheus.retentionTime`) and
only listens locally; Grafana reaches it through the bridge gateway address
`10.0.1.1:9090` (the host), which is the only port opened on the `nerdctl0`
firewall interface for this stack.

## Components and ports

| Component | Runs on | Address | Source |
|-----------|---------|---------|--------|
| Prometheus | host | `127.0.0.1:9090` | `services.prometheus` |
| Alertmanager | host | `127.0.0.1:9093` | `services.prometheus.alertmanager` |
| node_exporter | host | `127.0.0.1:9100` | `services.prometheus.exporters.node` |
| smartctl_exporter | host (root) | `127.0.0.1:9633` | `services.prometheus.exporters.smartctl` |
| zfs_exporter | host | `127.0.0.1:9134` | `services.prometheus.exporters.zfs` |
| cAdvisor | host | `127.0.0.1:8080` | `services.cadvisor` (containerd socket) |
| blackbox_exporter | host | `127.0.0.1:9115` | `services.prometheus.exporters.blackbox` |
| nginx-exporter | host | `127.0.0.1:9113` | `services.prometheus.exporters.nginx` |
| zpool textfile script | host (root, timer) | writes `/run/prometheus-node-exporter/zpool.prom` | `prometheus-zpool-textfile.{service,timer}` |
| Grafana | container `10.0.1.23:3000` | https://grafana.internal.polpetta.online | `containers/grafana` |
| nginx stub_status | container `10.0.1.6:8082` | `/stub_status` (LAN-only allow/deny) | `containers/nginx/config/nginx.conf` |

Notes:

- node_exporter's `systemd` collector is **not** enabled upstream by default;
  it is explicitly enabled here, together with the textfile collector pointed
  at `/run/prometheus-node-exporter`.
- zfs_exporter provides pool usage and pool health (`zfs_pool_allocated_bytes`
  / `zfs_pool_size_bytes`, `zfs_pool_health`, ...); node_exporter's built-in
  `zfs` collector provides ARC stats (`node_zfs_arc_*`).
- zfs_exporter has no scrub metrics, so `prometheus-zpool-textfile` (a
  oneshot service run every 15 minutes by a timer, as root) parses
  `zpool status` and writes `zpool_scrub_state`, `zpool_scrub_last_completed_seconds`
  and `zpool_data_errors` into the node_exporter textfile directory.
- The Grafana image is not pulled; `containers/grafana` builds it from
  `pkgs.grafana` via `nix-snapshotter.buildImage` (tag `grafana:nix-local`).

## Scrapes

| Job | What |
|-----|------|
| `node` | node_exporter (CPU, memory, disks, network, hwmon temps, systemd units, ZFS ARC) |
| `smartctl` | SMART health/temperatures for all drives |
| `zfs` | pool usage, health, fragmentation |
| `cadvisor` | per-container CPU/memory from `containerd`; the scrape job relabels `container_label_nerdctl_name` into a `container` label and drops the bulky `container_label_*` labels |
| `nginx` | stub_status via nginx-exporter (request rate, connections) |
| `blackbox-http` | HTTP probes against every service container with a web UI |
| `blackbox-tcp` | TCP probes: bind9 (53), immich valkey (6379), immich postgres (5432) |
| `blackbox-https` | HTTPS probe of the nginx container pinning the
  `grafana.internal.polpetta.online` vhost/SNI — used to watch the wildcard
  certificate (`*.internal.polpetta.online`) expiry |

## Alerts

Defined in `system/hosts/serverone/monitoring.nix` (YAML generated at build
time by the Nix configuration). All alerts go to Telegram through
Alertmanager; severities are `warning` and `critical`.

| Alert | Trigger | Severity |
|-------|---------|----------|
| `HostDown` | `up{job="node"} == 0` for 3m | critical |
| `SystemdUnitFailed` | any failed unit (excluding user sessions) for 5m | warning |
| `ZfsPoolUsageWarning` | pool > 80% for 10m | warning |
| `ZfsPoolUsageCritical` | pool > 90% for 10m | critical |
| `ZfsPoolDegraded` | `zfs_pool_health == 1` for 5m | warning |
| `ZfsPoolFailed` | `zfs_pool_health >= 2` for 1m | critical |
| `ZfsDataErrors` | `zpool status` reports permanent errors for 5m | critical |
| `ZfsScrubOverdue` | last scrub older than 21 days for 1h | warning |
| `SmartDeviceFailing` | `smartctl_device_smart_status == 0` for 5m | critical |
| `SmartCriticalWarning` | `smartctl_device_critical_warning != 0` for 5m | critical |
| `SmartDeviceHot` | drive > 60°C for 10m | warning |
| `ContainerDown` | blackbox probe failing for 5m | critical |
| `CertificateExpiringSoon` | cert expiry < 14 days | warning |

`ZfsScrubOverdue` only fires once at least one scrub has completed (the
metric is absent otherwise). There is currently no scheduled scrub on
serverone; run `zpool scrub <pool>` manually or add a timer.

## Dashboards

Provisioned from `containers/grafana/dashboards/` into the "serverone"
folder, datasource uid `prometheus`:

- **serverone host** (`uid: serverone-host`): CPU, load, memory, hwmon
  temperatures, disk usage + IO, network, ZFS pool usage, ARC size/hit ratio,
  scrub state, SMART health and temperatures, failed systemd units.
- **serverone containers** (`uid: serverone-containers`): per-container CPU
  and memory (cAdvisor), HTTP/TCP service up/down tables, probe durations and
  status codes, TLS certificate time remaining, nginx request rate and
  connections.

Grafana provisioning is mounted read-only into the container:

- `provisioning/datasources/prometheus.yaml` →
  `/etc/grafana/provisioning/datasources/prometheus.yaml`
- `provisioning/dashboards/provider.yaml` →
  `/etc/grafana/provisioning/dashboards/provider.yaml`
- `dashboards/` → `/etc/grafana/dashboards`

State persists in `/mnt/SSD/apps/grafana/lib` (mounted at `/var/lib/grafana`).

## Adding a new container to probing

1. Give it an id/IP following `CONTAINERS.md`.
2. If it has a web UI, add `{ name = "<service>"; url = "http://10.0.1.<id>:<port>"; }`
   to `httpProbeTargets` in `system/hosts/serverone/monitoring.nix`; otherwise
   add `{ name = "<service>"; address = "10.0.1.<id>:<port>"; }` to
   `tcpProbeTargets`. The `name` becomes the `service` label shown on the
   dashboards and in the `ContainerDown` alert.
3. If it should be reachable through nginx, add the usual map entry in
   `containers/nginx/config/nginx.conf`.

The `ContainerDown` alert and the dashboard tables pick the new target up
automatically.

## The smartd change

`system/modules/smartd.nix` gained an opt-out,
`services.smartd.telegramNotify.enable` (default `true`). serverone sets it
to `false`: self-tests keep running, but smartd no longer notifies Telegram
directly — SMART failures now arrive through
smartctl_exporter → Prometheus → Alertmanager. computerone and portatilo
still use the direct Telegram notification, reading the same shared
`telegram-bot` secret block, so the telegram secrets are only declared where
notifications are enabled.

## Secrets the user must add

The following keys must be present in `serverone.yaml` of the nix-secrets
repo (deployment of secrets is manual, as usual):

| Key | Used by | Notes |
|-----|---------|-------|
| `telegram-bot` | Alertmanager Telegram receiver | shared block with `token` and `chat-id` (numeric id, rendered unquoted into the config); the nested keys `telegram-bot/token` and `telegram-bot/chat-id` are selected with sops `key` |
| `grafana` | Grafana | block with `admin-password` (admin login) and `secret-key`; both rendered into the `grafana-env` sops template |

`sops-nix` renders the two environment files (`alertmanager-telegram-env`
for Alertmanager, `grafana-env` for the Grafana container) from these keys at
`/run/secrets/rendered/` and restarts the affected units when they change.
