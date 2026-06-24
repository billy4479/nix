# Service Access Redesign

This document captures the current service exposure model, the problems with it, and the proposed redesign for access control and public routing of services hosted on `serverone`.

It is intentionally detailed so the design can be resumed later without reconstructing the whole conversation.

## Current Topology

`serverone` runs most services as containers on the `nerdctl` bridge subnet `10.0.1.0/24`.

Important container IPs today:

| Service | IP |
|---------|----|
| nginx | `10.0.1.6` |
| bind9 | `10.0.1.11` |
| headscale | `10.0.1.15` |
| frp client | `10.0.1.131` |

The public entrypoint is `vps-proxy`, whose public IPv4 address is `87.106.25.93`.

Current public HTTP flow:

```text
Internet
  -> vps-proxy:80/443
  -> frps
  -> frpc on serverone
  -> nginx:81/4443 with PROXY protocol
  -> backend container
```

Current internal HTTP flow:

```text
Tailnet or LAN client
  -> bind9 split-horizon DNS
  -> nginx directly at 10.0.1.6 or 192.168.2.21
  -> backend container
```

Current non-HTTP public flow:

```text
Internet
  -> vps-proxy public port
  -> frps
  -> frpc on serverone
  -> backend container
```

Headscale currently advertises the whole container subnet to the tailnet:

```text
10.0.1.0/24
```

This makes every routed container IP potentially reachable from tailnet clients unless another control blocks it.

## Current DNS

Public DNS is managed by Cloudflare. The current public zone has this important wildcard:

```dns
*.polpetta.online. 1 IN A 87.106.25.93 ; DNS-only
```

So every public subdomain currently lands on `vps-proxy`.

Local DNS is served by the bind9 container. It uses views for LAN and tailnet/container clients.

Current local behavior is mostly wildcard-based:

- LAN clients resolve `*.polpetta.online` and `*.internal.polpetta.online` to `192.168.2.21`.
- Tailnet/container clients resolve `*.polpetta.online` and `*.internal.polpetta.online` to `10.0.1.6`.

Headscale pushes bind9 as the global DNS server for tailnet clients:

```text
10.0.1.11
```

## Current Access Control

Internal HTTP access is currently controlled by nginx source IP rules in `restrict_internal.conf`:

```nginx
deny @@EXTERNAL_TRAFFIC@@;

allow 10.0.0.0/8;
allow 192.168.0.0/16;
deny  all;
```

This means:

- traffic arriving through FRP is denied for internal hosts;
- LAN clients are broadly trusted;
- tailnet clients are broadly trusted;
- nginx does not know which Headscale user owns a tailnet IP;
- all tailnet users can see all tailnet-accessible services;
- LAN and tailnet are treated as network locations, not identities.

## Problems To Solve

The current model has several pitfalls.

1. Tailnet membership is too broad.

   Family members are in the same tailnet. Today, any tailnet client can reach any internal service that nginx exposes.

2. LAN access is too broad.

   LAN access is needed for some devices, such as a smart TV using Jellyfin, but LAN should not automatically imply access to every internal service.

3. Public traffic lacks Cloudflare protection.

   Public services currently arrive through `vps-proxy` and FRP. Cloudflare Tunnel was used previously, but caused issues for services that are not normal HTTP, including UDP, raw TCP, and Headscale's non-standard WebSocket POST behavior.

4. The container subnet is over-advertised.

   Advertising `10.0.1.0/24` makes private backend services easier to reach directly from the tailnet.

5. Configuration is duplicated and manual.

   nginx, FRP, DNS, and future Cloudflare Tunnel config all describe related facts about the same services.

## High-Level Goal

Each service should declare its container definitions and access endpoints together in Nix.

That single source of truth should generate:

- nginx HTTP routing;
- nginx access policy behavior;
- auth-service policy;
- cloudflared ingress rules;
- FRP client/server config;
- local bind9 DNS records;
- specific Tailnet route advertisements.

Public Cloudflare DNS should still require minimal manual changes. Adding normal public HTTP services should not require touching the Cloudflare console.

## Shared Service Catalog

Service declarations should live in a shared `polpetta.services` module, not directly as host-local `nerdctl-containers` entries.

The catalog must be pure, side-effect-free data. Importing it on `vps-proxy` must not force evaluation of `serverone`-only secrets, host paths, generated files, or container materialization. Host-specific generators are responsible for turning this data into concrete `nerdctl-containers`, SOPS templates, nginx config, bind9 config, FRP config, and firewall rules.

Each service should have this shape:

```nix
polpetta.services.<name> = {
  containers = {
    <container-name> = {
      # Existing nerdctl container definition for this container.
      # This must stay declarative and safe to import on hosts that do not
      # materialize containers.
    };
  };

  access = [
    # Endpoint declarations.
  ];
};
```

The `containers` field embeds the existing container definitions. It is plural because some services are multi-container applications, such as Immich or Headscale. On `serverone`, a generator materializes `polpetta.services.<name>.containers` into `nerdctl-containers` entries.

The `access` field is the single source of truth for generated nginx, auth-service, cloudflared, FRP, bind9, firewall, and Headscale route behavior.

Hosts should control materialization through generator toggles. For example:

- `serverone` enables container, nginx, bind9, firewall, cloudflared, FRP client, and Headscale route generators;
- `vps-proxy` imports the same service catalog but enables only FRP server and firewall generators;
- other hosts do not need to materialize the catalog unless future generators require it.

This keeps endpoint declarations next to service/container definitions while still allowing multiple hosts to consume the same normalized endpoint list.

Catalog service containers must not publish arbitrary host ports manually. Service exposure should be generated from `access` declarations. Infrastructure containers such as nginx and bind9 are explicit exceptions, and generated port mappings for non-HTTP access endpoints are allowed.

Current raw service port mappings that must be converted into generated access exposure include Syncthing peer/discovery ports, qBittorrent peer ports, and Minecraft Java/Bedrock ports. nginx and bind9 remain infrastructure exceptions.

## Endpoint Model

Each service gets an `access` option which is a list of endpoints.

Every endpoint must have a name and hostname, even non-HTTP endpoints.

Example:

```nix
access = [
  {
    name = "web";
    hostname = "service.internal.polpetta.online";
    protocol = "http"; # "http", "tcp", or "udp"
    backendContainer = "service";
    backendPort = 8080;
    public = "none"; # "none", "cloudflareTunnel", or "frp"

    allowLan = false;
    allowedTailnetPrincipals = true;

    extraNginxConfig = # nginx
      ''
        proxy_read_timeout 3600;
      '';
  }
];
```

### Required Fields

`name`

Unique endpoint name within the service. Examples: `web`, `minecraft-java`, `minecraft-bedrock`, `postgres`.

`hostname`

Always required. This is used for HTTP routing, DNS records, documentation, and non-HTTP service discovery.

`protocol`

One of:

- `http`
- `tcp`
- `udp`

`backendPort`

The port exposed by the backend container.

`public`

Must be explicit on every endpoint. One of:

- `none`
- `cloudflareTunnel`
- `frp`

### Optional Fields

`backendContainer`

Default: the service's only container, if the service has exactly one container.

The catalog container that serves this endpoint. This is required when a service has multiple containers.

`allowLan`

Default: `false`.

If true, LAN clients may access this endpoint anonymously at the gateway/network layer. Application-level authentication remains the responsibility of the service.

This is independent from public exposure. A public endpoint is not automatically exposed through local LAN DNS or LAN routing unless `allowLan = true` is set explicitly.

`allowedTailnetPrincipals`

Default: `false`.

Tailnet access is denied unless an endpoint explicitly opts in with either `true` or a principal list.

This is a tri-state value:

```nix
allowedTailnetPrincipals = false;
```

Tailnet access is denied.

```nix
allowedTailnetPrincipals = true;
```

Tailnet access is allowed without custom gateway authentication and without JWT identity injection.

```nix
allowedTailnetPrincipals = [ "user:billy" "group:family" ];
```

Tailnet access requires the custom auth service. The auth service maps the source tailnet IP to a Headscale user, checks the configured principals, and returns a signed JWT for nginx to pass upstream.

This is independent from public exposure. A public endpoint is not automatically exposed through tailnet DNS, route advertisement, or tailnet authorization unless `allowedTailnetPrincipals` is set explicitly.

`extraNginxConfig`

Default: empty string.

Only valid for `protocol = "http"`.

This is injected inside the generated `location / { ... }` block after common proxy settings. It is meant for one-off service tuning, such as large uploads, long timeouts, disabled buffering, or streaming behavior.

Example:

```nix
extraNginxConfig = # nginx
  ''
    client_max_body_size 500000M;
    proxy_request_buffering off;
    proxy_read_timeout 3600;
    send_timeout 3600;
  '';
```

There should not initially be an arbitrary global or server-level nginx escape hatch.

`publicPort`

Not part of the initial model unless needed later.

For FRP endpoints, `publicPort` should default to `backendPort`. This is enough for the currently known cases.

For HTTP endpoints using FRP, `publicPort` does not create per-service `80`/`443` proxies. HTTP-over-FRP uses one shared HTTP/HTTPS proxy pair when at least one HTTP endpoint has `public = "frp"`.

## Example Endpoints

### Gateway-Authenticated Internal HTTP Service

```nix
access = [
  {
    name = "web";
    hostname = "ff.internal.polpetta.online";
    protocol = "http";
    backendPort = 4479;
    public = "none";

    allowLan = false;
    allowedTailnetPrincipals = [ "user:billy" "group:family" ];
  }
];
```

Behavior:

- no public access;
- LAN denied;
- tailnet access requires auth-service authorization;
- nginx passes a signed JWT upstream;
- application can skip its own login based on the verified JWT.

### Jellyfin-Like Internal Service

```nix
access = [
  {
    name = "web";
    hostname = "jellyfin.internal.polpetta.online";
    protocol = "http";
    backendPort = 8096;
    public = "none";

    allowLan = true;
    allowedTailnetPrincipals = true;
  }
];
```

Behavior:

- no public access;
- LAN allowed anonymously at gateway level;
- tailnet allowed without gateway identity;
- Jellyfin continues to provide app-native authentication.

### Public HTTP Service Through Cloudflare Tunnel

Cloudflare Tunnel is the preferred path for normal public HTTP services. Services with very large uploads, sync clients, or unusual long-lived request behavior may hit Cloudflare proxy limits or behavior differences. Those services can still start on Cloudflare Tunnel, but switching an endpoint from `public = "cloudflareTunnel"` to `public = "frp"` should remain easy if real usage shows problems.

For OpenCloud specifically, starting on Cloudflare Tunnel is an intentional trial. Migration validation should include large uploads, sync-client behavior, and long-running downloads. If those fail, OpenCloud should become an FRP HTTP exception rather than accumulating service-specific nginx/cloudflared hacks.

```nix
access = [
  {
    name = "web";
    hostname = "opencloud.polpetta.online";
    protocol = "http";
    backendPort = 9200;
    public = "cloudflareTunnel";

    allowLan = true;
    allowedTailnetPrincipals = true;

    extraNginxConfig = # nginx
      ''
        client_max_body_size 500000M;
        proxy_request_buffering off;
        proxy_read_timeout 3600;
        send_timeout 3600;
      '';
  }
];
```

Behavior:

- external users enter through Cloudflare Tunnel;
- LAN and tailnet users bypass Cloudflare using local DNS;
- no gateway JWT is issued;
- application provides its own authentication.

### Headscale Through FRP

```nix
access = [
  {
    name = "web";
    hostname = "headscale.polpetta.online";
    protocol = "http";
    backendPort = 8080;
    public = "frp";

    allowLan = true;
    allowedTailnetPrincipals = true;
  }
];
```

Behavior:

- external users/devices enter through VPS/FRP;
- LAN and tailnet users bypass FRP using local DNS;
- Cloudflare Tunnel is not used because Headscale has compatibility issues with Cloudflare Tunnel behavior;
- Headscale continues to provide its own protocol/authentication semantics.

Headscale STUN/DERP UDP `3478` is intentionally removed from the redesigned public exposure model. The first migration preserves the HTTP/control-plane path through FRP but deliberately drops the current UDP `3478` FRP/VPS exposure. UDP/STUN/DERP repair can be revisited separately later.

### Minecraft Runner With Multiple Endpoints

```nix
access = [
  {
    name = "web";
    hostname = "mc-runner.polpetta.online";
    protocol = "http";
    backendPort = 4479;
    public = "cloudflareTunnel";

    allowLan = true;
    allowedTailnetPrincipals = true;
  }
  {
    name = "minecraft-java";
    hostname = "mc.polpetta.online";
    protocol = "tcp";
    backendPort = 25565;
    public = "frp";

    allowLan = true;
    allowedTailnetPrincipals = true;
  }
  {
    name = "minecraft-bedrock";
    hostname = "mc.polpetta.online";
    protocol = "udp";
    backendPort = 19132;
    public = "frp";

    allowLan = true;
    allowedTailnetPrincipals = true;
  }
];
```

Behavior:

- web UI can use Cloudflare Tunnel if it is safe to expose publicly;
- Java and Bedrock traffic use FRP;
- LAN and tailnet clients bypass the public path where possible;
- Minecraft provides its own protocol-level access behavior.

### Container-Private Dependency

```nix
access = [
  {
    name = "postgres";
    hostname = "immich-pg.internal.polpetta.online";
    protocol = "tcp";
    backendPort = 5432;
    public = "none";

    allowLan = false;
    allowedTailnetPrincipals = false;
  }
];
```

Behavior:

- no public access;
- no LAN access;
- no tailnet access;
- container DNS can resolve this hostname to the backend container IP;
- LAN and tailnet DNS views should not expose this hostname;
- no `/32` route should be advertised for this container IP.

## Assertions

The Nix module should enforce these assertions.

`public` must be explicitly set on every endpoint.

Hostnames ending in `.internal.polpetta.online` must have:

```nix
public = "none";
```

If `public != "none"`, then:

```nix
! lib.hasSuffix ".internal.polpetta.online" hostname
```

Public exposure, LAN access, and tailnet access are separate decisions. A public endpoint may also opt into LAN or tailnet access, but it must do so explicitly with `allowLan` and `allowedTailnetPrincipals`.

This prevents Cloudflare/FRP public transport controls from being bypassed accidentally by every LAN or tailnet client. Services that deliberately enable local bypass must still provide their own application authentication unless they use gateway-authenticated tailnet principals.

If `allowedTailnetPrincipals` is a list, then:

```nix
allowLan = false;
protocol = "http";
```

Rationale:

- gateway-authenticated services should not also allow anonymous LAN access;
- the custom auth gateway works only for HTTP.

If `public = "cloudflareTunnel"`, then:

```nix
protocol = "http";
```

Cloudflare Tunnel is the default public HTTP path, but it is not the general path for raw TCP/UDP.

If `extraNginxConfig` is non-empty, then:

```nix
protocol = "http";
```

If a service has more than one container, every endpoint must set `backendContainer` explicitly.

If a service has exactly one container, `backendContainer` may be omitted and defaults to that container.

Catalog service containers must not set raw manual `ports`. Host/VPS port exposure must be generated from endpoint declarations. Infrastructure generators may create explicit exceptions for nginx, bind9, FRP, and other gateway components.

Duplicate endpoint declarations should be rejected when they would produce ambiguous routing. In particular:

- duplicate HTTP hostnames are invalid, because path-level routing is intentionally out of scope;
- duplicate FRP raw TCP or UDP public port/protocol combinations are invalid;
- the same hostname may be used by distinct TCP and UDP endpoints when the protocol semantics are distinct, such as Minecraft Java and Bedrock.

## Public DNS Strategy

Public DNS remains managed by Cloudflare.

The current wildcard points to the VPS:

```dns
*.polpetta.online. 1 IN A 87.106.25.93 ; DNS-only
```

The proposed public DNS model is to change the wildcard to the Cloudflare Tunnel:

```dns
*.polpetta.online. 1 IN CNAME <tunnel-id>.cfargotunnel.com. ; proxied
```

Then add explicit DNS-only records only for FRP exceptions:

```dns
headscale.polpetta.online. 1 IN A 87.106.25.93 ; DNS-only
mc.polpetta.online.        1 IN A 87.106.25.93 ; DNS-only
```

This gives these properties:

- most new public HTTP services require only Nix changes;
- FRP exceptions require rare explicit Cloudflare DNS records;
- public wildcard DNS does not imply wildcard app exposure, because cloudflared/nginx generated config controls which hostnames exist;
- LAN and tailnet clients bypass public DNS by using generated local bind9 records.

This wildcard is an intentional convenience tradeoff. It increases the blast radius of a bad endpoint declaration: if a hostname is accidentally marked `public = "cloudflareTunnel"`, public DNS will already resolve it. Therefore these controls are hard requirements, not optional hardening:

- `public` must be explicit on every endpoint;
- cloudflared ingress must be generated as an exact hostname allowlist ending in `http_status:404`;
- nginx Cloudflare listener server blocks must be generated as exact public hostnames, not broad wildcards;
- local LAN/tailnet access must remain explicit and must not be inferred from public exposure.

Cloudflare DNS automation is out of scope for the initial implementation. It can be added later with Terraform/OpenTofu or a Cloudflare API integration if manual FRP exceptions become annoying.

## Local DNS Generation

bind9 local zones should be generated from endpoint declarations rather than handwritten wildcard records.

DNS records are for discovery, convenience, and avoiding accidental access. DNS omission is not an authorization boundary. Actual access enforcement belongs to nginx policy, auth-service policy, and generated firewall rules.

Generated zones must also support declarative static records that are not service endpoints. The current zones include records such as the apex GitHub Pages records, `www`, `quote-book`, and `external`. Those should not disappear just because service records become generated.

Static records and generated endpoint records should be merged per zone/view. The generator should reject collisions unless an explicit override mechanism is added later.

The desired views are:

### Container View

The container view should resolve declared endpoint hostnames according to protocol.

For HTTP endpoints, resolve to nginx:

```dns
ff.internal.polpetta.online. A 10.0.1.6
opencloud.polpetta.online.   A 10.0.1.6
```

This keeps container clients on the same hostname/TLS/nginx path as LAN and tailnet clients, and avoids bypassing nginx behavior such as auth, proxy headers, upload tuning, and WebSocket handling.

For non-HTTP endpoints and container-private dependencies, resolve to the backend container IP:

Examples:

```dns
immich-pg.internal.polpetta.online. A 10.0.1.130
mc.polpetta.online.                 A 10.0.1.13
```

This gives containers direct service discovery for dependencies and raw TCP/UDP services without bypassing nginx for HTTP app hostnames.

### Tailnet View

The tailnet view should expose only tailnet-allowed endpoints.

For HTTP endpoints with `allowedTailnetPrincipals != false`, resolve to nginx:

```dns
service.internal.polpetta.online. A 10.0.1.6
```

For non-HTTP endpoints with `allowedTailnetPrincipals = true`, resolve to the backend container IP:

```dns
mc.polpetta.online. A 10.0.1.13
```

For endpoints with `allowedTailnetPrincipals = false`, do not emit tailnet DNS records.

### LAN View

The LAN view should expose only LAN-allowed endpoints.

For HTTP endpoints with `allowLan = true`, resolve to the server LAN/nginx address:

```dns
jellyfin.internal.polpetta.online. A 192.168.2.21
```

For non-HTTP endpoints with `allowLan = true`, either resolve to a reachable backend/container address if routing supports it, or defer until LAN routing is designed. The initial focus can be HTTP LAN access.

For endpoints with `allowLan = false`, do not emit LAN DNS records.

### Unknown Names

The generated DNS model should eventually remove broad local wildcard records. This prevents LAN/tailnet users from discovering or accidentally resolving names that are not explicitly declared.

## Tailnet Route Advertisement

Route advertisement is not the security boundary. It is a reachability and ergonomics mechanism.

The redesign must also generate firewall policy on `serverone` so tailnet and LAN clients cannot directly reach backend container IPs unless the endpoint explicitly allows that access. This avoids relying on absence of a route as authorization, and protects against future route drift, stale client routes, exit-node behavior, or accidental broad subnet advertisement.

`serverone` currently also advertises itself as an exit node. That makes reduced `/32` route advertisement useful for ergonomics and least-reachability, but not sufficient as a protection boundary. Firewall policy must be treated as the real direct-backend access control layer.

The current route advertisement should change from:

```text
10.0.1.0/24
```

to a generated list of `/32` routes.

Always advertise:

```text
10.0.1.6/32   # nginx
10.0.1.11/32  # bind9
```

Also advertise backend container IP `/32` routes for non-HTTP endpoints where tailnet direct access is enabled:

```nix
protocol = "tcp"; # or "udp"
allowedTailnetPrincipals = true;
```

Do not advertise `/32` routes for container-private dependencies such as Postgres or Valkey.

This reduces unnecessary tailnet reachability, but it is only one layer. Generated firewall rules are still required to block direct access to private backend containers.

## Firewall Enforcement

`serverone` should generate firewall rules from the same endpoint list.

The firewall should:

- allow tailnet clients to reach always-needed infrastructure IPs such as nginx and bind9;
- allow tailnet clients to reach backend container IPs only for non-HTTP endpoints with `allowedTailnetPrincipals = true`;
- allow LAN clients to reach backend container IPs only for explicitly supported non-HTTP LAN endpoints;
- deny tailnet and LAN direct access to container-private dependencies and HTTP backends that should only be reached through nginx;
- keep container-to-container traffic on the bridge working for declared private dependencies.

Nginx and auth-service policy remain responsible for HTTP authorization. Firewall policy prevents bypassing nginx by connecting directly to backend container IPs.

## Nginx Design

There should be one nginx container, not multiple nginx services.

That single nginx should have multiple ingress listeners with different trust semantics.

Real-client-IP handling must be listener-specific. Shared snippets may contain common security headers and proxy settings, but must not contain `real_ip_header`, `set_real_ip_from`, or other trust decisions that would accidentally apply to every listener.

### Direct LAN/Tailnet Listener

This listener serves direct local clients:

```text
:80
:443
```

It handles:

- LAN direct HTTP access;
- tailnet direct HTTP access;
- gateway-authenticated internal services;
- direct bypass for public services when clients are on LAN or tailnet.

It must not trust Cloudflare headers.

It must not trust PROXY protocol.

It must clear any inbound identity headers before proxying. In particular, clients must not be able to supply `X-Polpetta-Identity` directly.

### FRP Listener

This listener serves HTTP services that are public through FRP:

```text
:81 with PROXY protocol
:4443 with PROXY protocol
```

It should continue to use PROXY protocol so nginx can recover the real external client IP from FRP.

Only this listener should trust PROXY protocol. The `real_ip_header proxy_protocol` configuration belongs in FRP-specific server/listener config, not in shared snippets.

It should only expose HTTP endpoints with:

```nix
public = "frp";
protocol = "http";
```

It should not expose internal-only hostnames.

### Cloudflare Tunnel Listener

This listener serves HTTP services that are public through Cloudflare Tunnel:

```text
:8080 plain HTTP
```

Cloudflared connects to nginx over plain HTTP on the private container bridge.

This listener should:

- allow only the cloudflared container IP;
- deny all other sources;
- trust `CF-Connecting-IP` only on this listener;
- force upstream forwarded scheme semantics for the original public request, for example `X-Forwarded-Proto https`, because cloudflared connects to nginx over plain HTTP;
- expose only HTTP endpoints with `public = "cloudflareTunnel"`.

The implementation must verify nginx real-IP ordering. If `real_ip_header CF-Connecting-IP` rewrites `$remote_addr` before access checks, the listener must validate the original peer address using an appropriate nginx variable/map/geo pattern rather than relying on a naive `allow <cloudflared-ip>; deny all;` after real-IP processing.

Example generated shape:

```nginx
server {
  listen 8080;
  server_name opencloud.polpetta.online;

  allow 10.0.1.<cloudflared-id>;
  deny all;

  real_ip_header CF-Connecting-IP;

  location / {
    proxy_pass http://10.0.1.14:9200;
    include /etc/nginx/snippets/proxy.conf;
  }
}
```

Only this listener should trust `CF-Connecting-IP`.

The Cloudflare listener should not reuse a generic proxy snippet that forwards `X-Forwarded-Proto $scheme` unless that snippet can be parameterized. On this listener `$scheme` is `http`, but upstream applications should generally see the original public scheme as `https`.

## Auth Service

A custom HTTP auth service should run as a private container on the container bridge.

It should not have a user-facing nginx vhost.

It should not be reachable from LAN, tailnet, or public ingress.

Nginx calls its authorization endpoint directly by container IP for protected HTTP endpoints.

Applications that need JWT verification fetch JWKS directly from the auth service over the container bridge.

The auth service has two different trust surfaces:

- authorization checks, which are privileged and must only accept nginx-originated requests;
- JWKS/public-key reads, which are read-only and may be reachable by JWT-aware application containers.

These surfaces may be implemented as separate ports, listeners, paths with strict middleware, or another equivalent split. The authorization surface must have both network-level restriction and an application-level guard such as a shared secret header from nginx. It must reject spoofed client-IP or identity headers from arbitrary container peers.

### Source IP Prerequisite

Principal-based tailnet authentication depends on nginx seeing the real tailnet client IP.

Before enabling any endpoint with list-valued `allowedTailnetPrincipals`, deployment must validate what source IP reaches nginx through the intended tailnet path. If subnet routing SNAT hides the original tailnet client IP, principal-based auth must not be enabled until routing is adjusted, for example by disabling SNAT for subnet routes if that is appropriate for the deployment.

This prerequisite should be part of migration validation, not an assumption in the auth-service implementation.

### Responsibilities

The auth service should:

- accept nginx `auth_request` calls;
- authenticate that the `auth_request` came from nginx;
- inspect the source client IP passed by nginx only after authenticating nginx as the caller;
- determine whether the IP is a Headscale tailnet IP;
- query Headscale's HTTP API to map tailnet IP to Headscale user and node metadata;
- check the requested hostname against generated policy;
- expand groups from its own config;
- issue a signed JWT when authorization succeeds;
- expose a JWKS endpoint for applications.

### Headscale API

The auth service should use Headscale's HTTP API, not read Headscale's SQLite database.

A long-lived Headscale API key should be stored in SOPS and mounted into the auth service container.

### Cache Behavior

Cache behavior can be internal auth-service configuration, not exposed in every service endpoint.

Suggested behavior:

- cache IP-to-user/node mappings for a short TTL;
- if Headscale is unavailable, continue using stale cache only for a short configured grace period;
- emit warnings loudly when serving stale cache;
- after grace expires, fail closed for protected services.

If Headscale is unavailable, that is already a critical infrastructure problem, so temporary stale-cache serving is acceptable. The grace period should stay short because stale mappings delay revocation after a Headscale user, node, or route assignment changes.

### Groups

Group membership should be auth-service configuration, not Nix endpoint metadata.

Example auth-service config:

```yaml
headscale:
  url: http://10.0.1.15:8080
  apiKeyFile: /run/secrets/headscale-auth-api-key

groups:
  family:
    - billy
    - alice

cache:
  ttl: 5m
  staleGrace: 10m

jwt:
  privateKeyFile: /run/secrets/internal-auth-jwt-private-key
  keyId: primary
```

### Generated Policy

Nix should generate auth-service policy only for HTTP endpoints where `allowedTailnetPrincipals` is a list.

Example generated policy:

```json
{
  "services": {
    "ff.internal.polpetta.online": {
      "allowedTailnetPrincipals": ["user:billy", "group:family"]
    }
  }
}
```

No path-level policy is needed. Path-level authorization stays app-native.

## JWT Contract

Nginx should pass a single signed JWT header to upstream applications only when `allowedTailnetPrincipals` is a list.

Suggested header:

```text
X-Polpetta-Identity: <jwt>
```

Nginx must clear any inbound `X-Polpetta-Identity` before setting its own value.

Nginx must also clear this header on routes that do not perform gateway authorization, so upstream applications never see a client-supplied identity token.

Applications that consume this header must not trust header presence alone. They must reject missing or empty tokens and verify the JWT signature using the auth-service JWKS, including at least issuer, audience, and expiration checks.

Firewall policy is not the token trust boundary. Direct backend access may be blocked for other reasons, but JWT-aware applications are expected to remain safe even if a request reaches them without going through the gateway, because missing or forged tokens are rejected.

JWTs should be asymmetric.

Recommended approach:

- auth service stores the private signing key in SOPS;
- apps fetch public keys from the auth service JWKS endpoint;
- JWT header contains `kid`;
- use Ed25519/EdDSA if all relevant app libraries support it, otherwise use RS256 for broader compatibility.

Suggested claims:

```json
{
  "iss": "polpetta-auth",
  "aud": "ff.internal.polpetta.online",
  "sub": "billy",
  "username": "billy",
  "tailnet_ip": "100.x.y.z",
  "node_id": "...",
  "node_name": "...",
  "iat": 123,
  "exp": 456
}
```

Important JWT semantics:

- JWT is only emitted when gateway authorization was actually performed;
- `allowedTailnetPrincipals = true` does not emit JWT;
- LAN access never emits JWT;
- public Cloudflare/FRP access never emits JWT;
- `aud` should be the hostname to avoid token reuse across services;
- expiration should be short, such as 1-5 minutes, because nginx can refresh it per request.

## Cloudflared Design

A `cloudflared` container should be reintroduced.

It should receive generated ingress config for endpoints where:

```nix
public = "cloudflareTunnel";
protocol = "http";
```

Generated ingress should forward all public HTTP services to the dedicated nginx Cloudflare listener:

```yaml
ingress:
  - hostname: opencloud.polpetta.online
    service: http://10.0.1.6:8080
  - hostname: calendar-proxy.polpetta.online
    service: http://10.0.1.6:8080
  - service: http_status:404
```

Cloudflared should not route directly to backend containers, because nginx is responsible for:

- real client IP handling via `CF-Connecting-IP`;
- common proxy headers;
- shared security headers;
- large upload and timeout tuning;
- keeping all public HTTP routing in one place.

## FRP Generation

FRP should be generated for endpoints where:

```nix
public = "frp";
```

For HTTP endpoints, FRP should point to nginx's FRP listener, as it does today:

```text
remote 80  -> nginx 81  with PROXY protocol
remote 443 -> nginx 4443 with PROXY protocol
```

These HTTP proxies are shared. If one or more HTTP endpoints use `public = "frp"`, generate exactly one `80 -> nginx:81` proxy and exactly one `443 -> nginx:4443` proxy. Do not generate one 80/443 proxy pair per endpoint. Nginx is responsible for exposing only the generated set of FRP-public HTTP hostnames.

For TCP/UDP endpoints, FRP should point directly to the backend container IP and `backendPort`.

`publicPort` should initially default to `backendPort`.

Example generated FRP proxies:

```toml
[[proxies]]
name = "minecraft-java"
type = "tcp"
localIP = "10.0.1.13"
localPort = 25565
remotePort = 25565

[[proxies]]
name = "minecraft-bedrock"
type = "udp"
localIP = "10.0.1.13"
localPort = 19132
remotePort = 19132
```

The FRP server on `vps-proxy` should also generate `allowPorts` and firewall allowed ports from the same endpoint list.

## Public, LAN, Tailnet, And Container Semantics

### Public Access

Public access means an external internet user can reach the endpoint.

Public modes:

- `cloudflareTunnel`: for normal HTTP services;
- `frp`: for Headscale, raw TCP, UDP, and any HTTP service incompatible with Cloudflare Tunnel;
- `none`: no public exposure.

Cloudflare should provide transport/protection only. Cloudflare Access is not part of this design. Public services must provide their own app-native authentication.

Public access does not imply LAN access or tailnet access. If a public service should also be reachable directly from LAN or tailnet through split-horizon DNS, that must be declared explicitly on the endpoint.

### LAN Access

LAN access is anonymous at the gateway layer.

This is needed for devices that cannot run Tailscale, such as a smart TV using Jellyfin.

LAN access should be explicit per endpoint via:

```nix
allowLan = true;
```

This remains explicit even for public services.

LAN clients should continue to use the local DNS server, including for ad blocking.

### Tailnet Access

Tailnet access is controlled by `allowedTailnetPrincipals`.

For HTTP services, a list value enables Headscale-user authentication and JWT identity injection.

For non-HTTP services, list-valued `allowedTailnetPrincipals` is invalid. Non-HTTP services exposed to tailnet must rely on their own protocol/application authentication.

This remains explicit even for public services.

### Container Access

Container-to-container access is allowed by the container bridge and container DNS.

The auth service, Postgres, Valkey, and similar dependencies can be declared as endpoints with all ingress disabled:

```nix
public = "none";
allowLan = false;
allowedTailnetPrincipals = false;
```

Their hostnames should be resolvable only in the container DNS view.

## Suggested Migration Sequence

Use a staged rollout. The final architecture can still be implemented in one coherent set of modules, but behavior should be enabled layer by layer so failures are attributable and rollback is simple.

At minimum, keep the previous static nginx, bind9, FRP, and Headscale route configuration easy to restore from the previous system generation until the new path is validated.

Recommended stages:

1. Add the shared pure `polpetta.services` module with `containers`, `access` endpoint declarations, generator toggles, and assertions. Do not change runtime behavior yet.

2. Move existing `nerdctl-containers` definitions into `polpetta.services.<name>.containers` and add access declarations next to them. Preserve current generated/materialized `nerdctl-containers` behavior.

3. Generate a normalized list of all endpoints with derived backend container IPs. Validate that it matches the intended current service map.

4. Generate nginx config equivalent to current behavior and compare it before switching nginx to the generated config. After switching, validate direct LAN/tailnet HTTP and FRP HTTP behavior.

5. Generate bind9 zones/views from endpoint declarations plus static DNS records. During this stage, a temporary local fallback wildcard may be kept if needed for migration safety, but the target state is explicit generated records.

6. Generate FRP client config on `serverone` and FRP server config/firewall ports on `vps-proxy`. HTTP-over-FRP should use the shared 80/443 proxy pair. Headscale UDP `3478` should be removed deliberately in this stage if it has not already been removed.

7. Add cloudflared container and generated ingress config for `public = "cloudflareTunnel"` endpoints. Change Cloudflare public DNS manually when ready:

   ```dns
   *.polpetta.online CNAME <tunnel-id>.cfargotunnel.com ; proxied
   headscale.polpetta.online A 87.106.25.93             ; DNS-only
   mc.polpetta.online A 87.106.25.93                    ; DNS-only
   ```

8. Add generated `serverone` firewall enforcement for tailnet/LAN access to backend container IPs. Because `serverone` is also an exit node, validate that direct backend access is controlled by firewall policy, not just by narrower advertised routes.

9. Replace the broad `10.0.1.0/24` Headscale route advertisement with generated `/32` routes after firewall behavior has been validated.

10. Validate that nginx sees real tailnet client IPs on the intended path. Do not enable list-valued `allowedTailnetPrincipals` until this is proven.

11. Add the private auth service container, SOPS secrets, strict auth/JWKS split, mounted config, generated policy, and nginx `auth_request` integration.

12. Enable gateway-authenticated services one at a time.

Each stage should build `serverone` and `vps-proxy` before deployment and should have a small behavioral checklist before proceeding to the next stage.

## Validation

Nix build checks:

```sh
nix build .#nixosConfigurations.serverone.config.system.build.toplevel
nix build .#nixosConfigurations.vps-proxy.config.system.build.toplevel
```

Behavioral checks after deploy:

- external public Cloudflare Tunnel HTTP service resolves to Cloudflare and reaches app through nginx;
- Cloudflare Tunnel HTTP service receives correct forwarded HTTPS semantics upstream, including `X-Forwarded-Proto: https`;
- OpenCloud large uploads, sync-client behavior, and long-running downloads work if it remains on Cloudflare Tunnel;
- external `headscale.polpetta.online` resolves to VPS and continues to work through FRP;
- Headscale UDP `3478` is no longer publicly exposed after the intentional removal stage;
- external `mc.polpetta.online` resolves to VPS and Minecraft TCP/UDP still works;
- tailnet `opencloud.polpetta.online` resolves locally and bypasses Cloudflare;
- LAN `opencloud.polpetta.online` resolves locally and bypasses Cloudflare;
- public services that do not explicitly enable LAN/tailnet access do not receive local DNS records and are not reachable through local bypass paths;
- LAN `jellyfin.internal.polpetta.online` works;
- LAN media-management services with `allowLan = false` do not resolve or are denied;
- nginx sees the real tailnet client IP before enabling any list-valued `allowedTailnetPrincipals` endpoint;
- tailnet gateway-authenticated service returns JWT to upstream;
- a non-authorized Headscale user is denied by the auth service;
- direct calls to the auth-service authorization endpoint from non-nginx containers fail even with spoofed client-IP headers;
- JWT-aware applications reject missing, empty, expired, wrong-audience, or forged `X-Polpetta-Identity` tokens;
- inbound client-supplied `X-Polpetta-Identity` is cleared on routes that do not perform gateway auth;
- direct tailnet access to private backend containers such as Postgres no longer works after removing `10.0.1.0/24` route;
- generated firewall policy blocks direct LAN/tailnet access to HTTP backend containers that should only be reached through nginx;
- container-to-container private hostnames still resolve and work;
- static DNS records such as the apex GitHub Pages records, `www`, `quote-book`, and `external` still resolve in the intended views;
- generated configs do not contain manual service-container host port mappings outside generated access exposure and infrastructure exceptions.

## Open Questions

These questions remain open for implementation time.

1. Which exact language/runtime should the auth service use?

2. Which JWT algorithm should be selected: Ed25519/EdDSA or RS256?

3. What exact Headscale HTTP API endpoint returns node/user/IP mappings in the installed Headscale version?

4. Should LAN non-HTTP endpoints be supported immediately, or deferred until there is a concrete service that needs them?

5. Should public FRP DNS exceptions eventually be managed declaratively through Cloudflare's API?

6. Should generated bind9 zones keep a fallback wildcard during migration, or remove wildcards immediately to enforce explicit records?

7. How should generated configs be split across derivations so `serverone` and `vps-proxy` can both consume the normalized endpoint list cleanly? The catalog shape is decided: use pure `polpetta.services.<name>.containers` plus `polpetta.services.<name>.access`, with host-level generator toggles.

8. What exact mechanism should protect the auth-service authorization surface in addition to network source checks: shared secret header, mTLS, Unix socket, or something else?

9. If source-IP validation shows tailnet subnet-routed traffic is SNATed, what exact Headscale/Tailscale routing change should be used before enabling principal-based gateway auth?

10. Should the auth service expose metrics, and if so, should metrics be container-private only?
