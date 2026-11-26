# `polpetta.services` — service definition API

Under this API a single service file declares its container, where it is
reachable (domain), and who can reach it (access tier); the nginx vhost, the
vps edge DNAT forwards and the bind9 records are generated from that
declaration.

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
    # copyToRoot / entrypoint / cmd / volumes / environment / dependsOn / ...
  };

  # At most one proxied (HTTP) endpoint. Its presence generates the nginx vhost.
  web = {
    port = 4479;
    access = "public";             # "public" | "tailnet" | "tailnet-only" | "local" | "admin-only"
    # domain = "...";              # optional override, see "Domains"
    # probe.enable = false;       # opt out of the blackbox probe
    # probe.unauth = true;        # accept 401/404 as alive (default false)
    # probe.path = "/admin";      # blackbox probe path (default "")
    # probe.headers = { };        # extra HTTP headers sent by the probe
    #                             # (generates an http_custom_<name> module)
    # probe.timeout = "5m";       # per-probe timeout override (http probes
    #                             # default 30s; moves the probe to the slow
    #                             # blackbox job)
    # nginx.extraConfig = ''       # raw nginx text, injected into location /
    #   client_max_body_size 10M;
    # '';
  };

  # Raw TCP/UDP ports, independent of the web endpoint. `access = "public"`
  # is forwarded from the vps edge (DNAT over the wireguard tunnel); tailnet
  # and local are never forwarded. Direct access is filtered on the host and
  # bridge according to the tier/allowlist.

  raw = [
    {
      port = 25565;                # remotePort defaults to port
      proto = "tcp";               # or "udp"
      access = "public";
      # allowedSources = [ "10.0.1.3/32" ]; # optional direct-access allowlist
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

`local`, `tailnet`, and `public` are cumulative. `tailnet-only` and `admin-only` apply only to `web`:

| tier      | reachable from                          |
|-----------|-----------------------------------------|
| `local`   | LAN only (RFC1918)                      |
| `tailnet` | LAN + tailnet (100.64.0.0/10)           |
| `tailnet-only` | Tailnet only by default; explicit service sources may be added |
| `public`  | everyone (internet via the vps edge)    |
| `admin-only` | Headscale `group:admin` over Tailscale only |

Ordinary vhosts use shared listeners and check the **real client IP**
(restored from PROXY protocol for the edge listener). Both the vps tunnel IP and the
retiring frp address are trusted for PROXY protocol and explicitly denied for
non-public tiers as defense in depth during migration. Reserve `10.0.1.131`
until its compatibility entry is removed after migration and rollback needs
have ended.

`admin-only` vhosts are separate from the shared listeners. A dedicated
subnet-routed IP on TCP 443 is authorized by Headscale and DNAT'd only from
`tailscale0`. `web.integrationClients` can allow named service containers to
reach the backend on the bridge without granting web ingress. See the
[admin-only deployment guide](deployments/admin-only.md) before enabling it.

Independent nftables hooks deny unsolicited traffic to service container IPs,
including routed and same-bridge traffic, unless it matches a declared native
endpoint or comes from nginx to the declared web port. Host-originated traffic
bypasses service ingress checks. `allowedSources` replaces the tier's default
IPv4 ranges. Public raw endpoints allow arbitrary sources only via `wg0`; on
other paths the endpoint's CIDRs or private tier defaults apply.

The caches allow only their own application container, and PostgreSQL allows
only Immich and Outline, in addition to the host. DNS uses `tailnet`, because
VPN clients and service containers need it.

`polpetta-raw-firewall.service` loads this policy before containerd, which
requires it. Its reload is an atomic ruleset replacement; restarting the
ordinary NixOS firewall does not remove the raw-port policy.

The access tier is independent of the domain suffix; the suffix remains purely
a DNS/certificate convention (see below).

## Domains

Defaults keep the existing wildcard DNS + wildcard certificate working:

- `access = "public"` → `<name>.polpetta.online`
- otherwise → `<name>.internal.polpetta.online`

`web.domain` overrides the default. bind9 serves both zones as wildcards to
LAN (→ 192.168.2.21) and tailnet (→ 10.0.1.6) clients. In the tailnet
view, `admin-only` names override the wildcard to `10.0.2.6`. Public DNS (cloudflare) already
wildcards `*.polpetta.online` to the vps.

## What gets generated

| Target              | Generated from                                   |
|---------------------|--------------------------------------------------|
| nginx vhost         | `web`: listener(s) and tier ACL, TLS/headers snippets, `extraConfig` in `location /`, and a backend selected by vhost |
| vps edge DNAT forwards | `raw` entries with `access = "public"` (`remotePort`; `<vps IP>:<remotePort> → container IP:port` over the wireguard tunnel, source addresses preserved) |
| host and bridge raw-port firewall | non-public `raw` tiers, or any `allowedSources` override; loaded independently of the CNI filter chains |

| bind9 zone records  | `raw` entries with `record` (→ container IP, wg/tailnet view) |
| blackbox probes     | local nginx HTTPS for ordinary `web` endpoints, direct host HTTP probes for `tailnet-only` and `admin-only` backends, and direct TCP for `raw` entries with `probe.enable = true` |
| `useNginx` ordering | presence of `web` (auto-set on the mirrored container) |

Container `ports` (host publishing, e.g. LAN Minecraft) stay explicit on the
container. A published native port also needs a matching `raw` entry under
strict ingress. Do not publish a web backend port.

The nginx 80/443 edge, the vps DNAT plumbing and the static
zone/SOA data stay hand-written: they are infrastructure, not per-service.
So is the homepage vhost (`polpetta.online` apex + `www` redirect, content
in `sites/homepage/`, mounted into the nginx container at `/srv/homepage`):
it is plain static files with no backend container, and the apex name is
not a `.polpetta.online` subdomain, so it cannot be a service entry.

Non-public raw ports are not forwarded from the edge: reachability is
inherent (subnet router + LAN routing to container IPs), and the generated
raw-port firewall still enforces the tier or explicit application allowlist.
The `record` option only makes them addressable by name.


## Assertions

- domains unique across services
- `remotePort`s unique across public `raw` entries (only public entries are
  forwarded from the edge; local/tailnet ports stay on the bridge and may
  repeat)
- `record` names unique across services
- container IDs unique across all containers (services plus infrastructure);
  duplicate IDs would mean duplicate IPs on the bridge
- `probe.unauth` is false on tcp (raw) probes; it only applies to http
- non-public domains fall under `.internal.polpetta.online`, public ones under
  `polpetta.online` (wildcard DNS + cert are the only PKI)
- `access` is one of the allowed values for that endpoint type

## Host wiring

- Both serverone and vps-proxy import `services/services/` (its default.nix
  pulls in module.nix and every service file, so the two hosts always
  evaluate the same service set). vps-proxy only consumes the
  edge DNAT projection.

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
      # copyToRoot, entrypoint, cmd, volumes, environmentFiles, environment, dependsOn ...
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
   (`module.nix`), nginx and certbot. (frp was later replaced by a wireguard
   tunnel + vps edge DNAT; see `docs/deployments/drop-frp.md`.)
