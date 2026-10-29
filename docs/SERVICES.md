# `polpetta.services` — service definition API

Under this API a single service file declares its container, where it is
reachable (domain), and who can reach it (access tier); the nginx vhost, the
frp tunnels, the vps firewall openings and the bind9 records are generated
from that declaration.

## Layout

```
services/
  module.nix              # polpetta.services option + all generators
  services/
    default.nix           # shared import: module.nix + every service file
    immich-server.nix     # one file per service: container + exposure
    grafana/              # directory when support files exist
      default.nix
      dashboards/
```

## Option shape

```nix
polpetta.services.<name> = {
  # Exactly one container per service. Same options as nerdctl-containers;
  # mirrored into nerdctl-containers.<name> on serverone only.
  container = {
    id = 13;
    # imageToBuild / volumes / environment / dependsOn / ... unchanged
  };

  # At most one proxied (HTTP) endpoint. Its presence generates the nginx vhost.
  web = {
    port = 4479;
    access = "public";             # "public" | "tailnet" | "local"
    # domain = "...";              # optional override, see "Domains"
    # probe.enable = false;       # opt out of the blackbox probe
    # probe.unauth = true;        # accept 401/404 as alive (default false)
    # probe.path = "/admin";      # blackbox probe path (default "")
    # probe.headers = { };        # extra HTTP headers sent by the probe
    #                             # (generates an http_custom_<name> module)
    # nginx.extraConfig = ''       # raw nginx text, injected into location /
    #   client_max_body_size 10M;
    # '';
  };

  # Raw TCP/UDP ports, independent of the web endpoint. `access = "public"`
  # is tunneled through frp; tailnet/local are never tunneled and exist to
  # declare (and optionally name or probe) the port.
  raw = [
    {
      port = 25565;                # remotePort defaults to port
      proto = "tcp";               # or "udp"
      access = "public";
      # record = "mc";             # optional bind9 record name → container IP
      # probe.enable = true;       # blackbox tcp_connect probe (tcp only)
    }
  ];
};
```

One container per service: multi-container applications are split into one
service file each (e.g. `immich-server`, `immich-ml`, `immich-redis`). Plumbing containers declare no `web` and no public `raw`
ports; they may still declare private raw ports to make a listen port
addressable or probed (e.g. `immich-redis` probes 6379). Inter-container
wiring is unchanged (`dependsOn`, hardcoded IPs in environment).

## Access model

Tiers are cumulative:

| tier      | reachable from                          |
|-----------|-----------------------------------------|
| `local`   | LAN only (RFC1918)                      |
| `tailnet` | LAN + tailnet (100.64.0.0/10)           |
| `public`  | everyone (internet via the frp tunnel)  |

Enforcement happens in nginx on the **real client IP** (restored from
proxy_protocol), so every vhost listens uniformly on 443 and 4443; the tier
only decides which ACL snippet is applied. The frp edge IP is explicitly
denied for non-public tiers as defense in depth.

The access tier is independent of the domain suffix; the suffix remains purely
a DNS/certificate convention (see below).

## Domains

Defaults keep the existing wildcard DNS + wildcard certificate working:

- `access = "public"` → `<name>.polpetta.online`
- otherwise → `<name>.internal.polpetta.online`

`web.domain` overrides the default. bind9 serves both zones as wildcards to
LAN (→ 192.168.2.21) and tailnet (→ 10.0.1.6) clients, so no per-service DNS
entries are needed for web endpoints. Public DNS (cloudflare) already
wildcards `*.polpetta.online` to the vps.

## What gets generated

| Target              | Generated from                                   |
|---------------------|--------------------------------------------------|
| nginx vhost         | `web`: one explicit server block (listen 443 + 4443 proxy_protocol, TLS/headers snippets, tier ACL, `extraConfig` in `location /`) plus the `map $host $backend` entries it proxies through |
| frpc proxies        | `raw` entries with `access = "public"`           |
| frps `allowPorts` + vps firewall | `raw` entries with `access = "public"` (`remotePort`; allowPorts ranges are proto-agnostic and deduplicated) |
| bind9 zone records  | `raw` entries with `record` (→ container IP, wg/tailnet view) |
| blackbox probes     | every `web` endpoint (URL/port inferred; `probe.enable`/`probe.unauth`/`probe.path`/`probe.headers` tune it) plus tcp probes of `raw` entries with `probe.enable = true`; consumed by serverone's monitoring.nix, which declares no targets itself |
| `useNginx` ordering | presence of `web` (auto-set on the mirrored container) |

Container `ports` (host publishing, e.g. LAN minecraft) stay explicit on the
container: publishing a web endpoint's port on the host would bypass the nginx
ACLs.

The nginx 80/443 edge forwards, the frps bind port/token and the static
zone/SOA data stay hand-written: they are infrastructure, not per-service.

Non-public raw ports are not tunneled: reachability is inherent (subnet router
+ LAN routing to container IPs); the `record` option just makes them
addressable by name.

## Assertions

- domains unique across services
- `remotePort`s unique across public `raw` entries (only public entries are
  tunneled through frp; local/tailnet ports stay on the bridge and may repeat)
- `record` names unique across services
- container IDs unique across all containers (services plus infrastructure);
  duplicate IDs would mean duplicate IPs on the bridge
- built image references match their container (`nix-snapshotter.buildImage
  name`/`tag` must be the service name and `nix-local`): the unit runs the
  image as `<name>:nix-local` with `--pull never`, so a mismatch would only
  surface as a crash loop at deploy time
- `probe.unauth` is false on tcp (raw) probes; it only applies to http
- non-public domains fall under `.internal.polpetta.online`, public ones under
  `polpetta.online` (wildcard DNS + cert are the only PKI)
- `access` is one of the three enum values

## Host wiring

- Both serverone and vps-proxy import `services/services/` (its default.nix
  pulls in module.nix and every service file, so the two hosts always
  evaluate the same service set). vps-proxy only consumes the
  frps/firewall projection.
- Any container runs only where `containers/module.nix` is imported: each
  service's `container` is mirrored into `nerdctl-containers.<name>` (service
  name = container name) there, which keeps the existing dependency inference
  (bind9, nginx, headscale).
- Service files must therefore stay importable on hosts without containers:
  gate host-specific definitions (sops secrets, sysctls, firewall) on the
  same structural test the module uses:

  ```nix
  sops.secrets.my-service-env = lib.mkIf (options ? nerdctl-containers) { };
  ```

## Examples

`services/services/immich-server.nix` — split app, web endpoint with nginx
overrides and a historical domain (the default would embed the container
name):

```nix
{
  polpetta.services.immich-server = {
    container = {
      # imageToBuild, volumes, environmentFiles, environment, dependsOn ...
      id = 3;
      dependsOn = [
        "postgresql"
        "immich-redis"
        "immich-ml"
      ];
    };

    web = {
      port = 2283;
      access = "tailnet";
      domain = "immich.internal.polpetta.online";
      nginx.extraConfig = ''
        client_max_body_size 50000M;
        proxy_request_buffering off;
        proxy_read_timeout 3600;
        send_timeout 3600;
      '';
    };
  };
}
```

Plumbing companion (`immich-redis.nix`): same minus the `web` block.

`services/services/game-server-runner/` — public web + several raw ports + DNS record,
with a historical domain (the default would embed the container name):

```nix
{
  polpetta.services.game-server-runner = {
    container = {
      id = 13; # ...
    };

    web = {
      port = 4479;
      access = "public"; # public endpoint
      domain = "mc-runner.polpetta.online"; # historical domain (was the old service's name)
    };

    raw = [
      {
        port = 25565;
        access = "public";
        record = "mc";
      }
      {
        port = 19132;
        proto = "udp";
        access = "public";
      }
    ];
  };
}
```

`services/services/lunamultiplayer.nix` — mixed tiers on one container.
Since the game-server-runner instance landed, the `web` port is the runner's
web UI (on the default public domain; Luna's own built-in website stays off);
see the service file for the runner config (env/config templates, `server.toml`):

```nix
{
  polpetta.services.lunamultiplayer = {
    container = {
      id = 20; # ...
    };

    web = {
      port = 4479;
      access = "public"; # game-server-runner web UI
    };

    raw = [
      {
        port = 8800;
        proto = "udp";
        access = "public";
      } # game traffic
    ];
  };
}
```

## Migration

Completed in one pass on a development branch:

1. `services/module.nix` + generators landed; infrastructure (nginx, frpc,
   frps, bind9) consumes `polpetta.generated.*`.
2. All services moved from `containers/` to `services/services/` (bind9
   included, as a plumbing service); the hand-written nginx map/vhosts, frpc
   proxies and the `mc` zone record were deleted.
3. `containers/` now holds only the infrastructure: the container engine
   (`module.nix`), nginx, frp and certbot.
