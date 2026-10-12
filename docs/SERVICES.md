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
    immich.nix            # one file per service: container + exposure
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
    # nginx.extraConfig = ''       # raw nginx text, injected into location /
    #   client_max_body_size 10M;
    # '';
  };

  # Raw TCP/UDP port forwards, independent of the web endpoint.
  raw = [
    {
      port = 25565;                # remotePort defaults to port
      proto = "tcp";               # or "udp"
      access = "public";
      # record = "mc";             # optional bind9 record name → container IP
    }
  ];
};
```

One container per service: multi-container applications are split into one
service file each (e.g. `immich`, `immich-db`, `immich-ml`, `immich-valkey`).
Plumbing containers simply declare no `web`/`raw`. Inter-container wiring is
unchanged (`dependsOn`, hardcoded IPs in environment).

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
- `remotePort`s unique across services
- `record` names unique across services
- referenced containers exist
- non-public domains fall under `.internal.polpetta.online`, public ones under
  `polpetta.online` (wildcard DNS + cert are the only PKI)
- `access` is one of the three enum values

## Host wiring

- Both serverone and vps-proxy import all the service files (explicit import
  lists). vps-proxy only consumes the frps/firewall projection.
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

`services/services/immich.nix` — split app, web endpoint with nginx overrides:

```nix
{
  polpetta.services.immich = {
    container = {
      # imageToBuild, volumes, environmentFiles, environment, dependsOn ...
      id = 3;
      dependsOn = [ "immich-db" "immich-valkey" "immich-ml" ];
    };

    web = {
      port = 2283;
      access = "tailnet";
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

Plumbing companion (`immich-db.nix`): same minus the `web` block.

`services/services/mc-runner/` — public web + several raw ports + DNS record:

```nix
{
  polpetta.services.mc-runner = {
    container = { id = 13; /* ... */ };

    web = {
      port = 4479;
      access = "public";               # → mc-runner.polpetta.online
    };

    raw = [
      { port = 25565; access = "public"; record = "mc"; }
      { port = 19132; proto = "udp"; access = "public"; }
      { port = 19132; proto = "tcp"; access = "public"; }
    ];
  };
}
```

`services/services/lunamultiplayer-server.nix` — mixed tiers on one container,
with an explicit domain (the default would embed the full container name):

```nix
{
  polpetta.services.lunamultiplayer-server = {
    container = { id = 20; /* ... */ };

    web = {
      port = 8900;
      access = "tailnet";              # internal status UI
      domain = "lunamultiplayer.internal.polpetta.online";
    };

    raw = [
      { port = 8800; proto = "udp"; access = "public"; }  # game traffic
    ];
  };
}
```

## Migration

Completed in one pass on a development branch:

1. `services/module.nix` + generators landed; infrastructure (nginx, frpc,
   frps, bind9) consumes `polpetta.generated.*`.
2. All services moved from `containers/` to `services/services/`; the
   hand-written nginx map/vhosts, frpc proxies and the `mc` zone record were
   deleted.
3. `containers/` now holds only the infrastructure: the container engine
   (`module.nix`), nginx, bind9, frp and certbot.
