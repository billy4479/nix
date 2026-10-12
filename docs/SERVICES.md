# `polpetta.services` — service definition API

Design for the replacement of the current `nerdctl-containers` + hand-written
nginx/frp configuration. Under this API a single service file declares its
container, where it is reachable (domain), and who can reach it (access tier);
the nginx vhost, the frp tunnels, the vps firewall openings and the bind9
records are generated from that declaration.

## Layout

```
services/
  module.nix              # polpetta.services option + all generators
  nginx-snippets/         # per-tier ACL and shared nginx snippets
  services/
    immich.nix            # one file per service: container + exposure
    grafana/              # directory only when support files exist
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
| nginx vhost         | `web`: one explicit server block (listen 443 + 4443 proxy_protocol, TLS/headers snippets, tier ACL, `extraConfig` in `location /`) |
| frpc proxies        | `raw` entries with `access = "public"`           |
| frps `allowPorts` + vps firewall | `raw` entries with `access = "public"` (`remotePort`) |
| bind9 zone records  | `raw` entries with `record` (→ container IP, lan/wg views) |
| nerdctl `ports`     | `web`/`raw` endpoints                            |
| `useNginx` ordering | presence of `web` (auto-set on the mirrored container) |

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

- Both serverone and vps-proxy import the service files (explicit import
  lists). vps-proxy only consumes the frps/firewall side.
- serverone sets `polpetta.services.exposeContainers = true`, which mirrors
  each `container` into `nerdctl-containers.<name>` (service name = container
  name) and keeps the existing dependency inference (bind9, nginx, headscale).

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

`services/services/mc-runner.nix` — public web + several raw ports + DNS record:

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

`services/services/lunamultiplayer.nix` — mixed tiers on one container:

```nix
{
  polpetta.services.lunamultiplayer = {
    container = { id = 20; /* ... */ };

    web = {
      port = 8900;
      access = "tailnet";              # internal status UI
    };

    raw = [
      { port = 8800; proto = "udp"; access = "public"; }  # game traffic
    ];
  };
}
```

## Migration

Incremental:

1. Land the module, generators and host wiring (no behavior change).
2. Migrate services one by one from `containers/` into `services/services/`,
   removing each service's hand-written nginx map/vhost and frpc proxy entries
   as it migrates. The legacy wildcard+map blocks remain for the not-yet
   migrated remainder.
3. When the last service is migrated, delete the legacy wildcard+map blocks,
   retire `useNginx`, and update `CONTAINERS.md`.
