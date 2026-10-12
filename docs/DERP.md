# DERP / STUN architecture

This document describes how the tailnet's DERP region `999` is wired up: both
the relay and STUN are served directly by `vps-proxy`, headscale (on
`serverone`) only runs the control plane and the admission endpoint.

## Region layout

Headscale runs in a `nerdctl` container on `serverone` (container id 15, IP
`10.0.1.15`) with its embedded DERP server **disabled**
(`derp.server.enabled: false` in `config.yaml`). The region it advertises is
hand written in `../services/services/headscale/derp-custom.yaml` (mounted in the
container at `/etc/headscale/derp-custom.yaml` and referenced by `derp.paths`
in `config.yaml`):

| Node   | Role       | Hostname               | IPv4           | Ports                       |
|--------|------------|------------------------|----------------|-----------------------------|
| `999a` | DERP relay | `derp.polpetta.online` | `87.106.25.93` | TCP 443 (`derper-derp`)     |
| `999b` | STUN only  | `derp.polpetta.online` | `87.106.25.93` | UDP 3478 (`derper-stun`)    |

Both nodes are `derper` processes running directly on `vps-proxy`
(system/hosts/vps-proxy/derper-derp.nix and derper-stun.nix). Since
`derp.server.enabled` is `false`, headscale does not generate any region of
its own — the map from `derp.paths` is the only source.

`derp.polpetta.online` must be a **DNS-only** record pointing at the vps:
DERP and STUN need raw TCP/UDP, a proxied (e.g. Cloudflare) record would
break them.

## Traffic flows

- **Control plane**: clients → `headscale.polpetta.online` → `frps` on
  `vps-proxy` → frp tunnel → `frpc` on `serverone` → nginx container (10.0.1.6,
  `:81`/`:4443` with PROXY protocol) → headscale `:8080` (container
  `10.0.1.15`).
- **DERP relay (`999a`)**: clients connect over TLS to
  `derp.polpetta.online:443`, an SNI demuxer on the vps (nginx stream,
  `ssl_preread` — sni-demux.nix) routes this hostname to the loopback-only
  `derper-derp` (127.0.0.1:8443), where TLS is terminated. The demuxer writes
  a PROXY protocol v1 header (it must: the dispatch block is the only stage
  that still knows the real client IP), so the DERP branch first rides a
  loopback hop whose `listen ... proxy_protocol` strips the header again
  before the PP-unaware derper sees the stream. Every other SNI goes to frps
  (remotePort 8444, firewall-closed from the internet) with the same header,
  which is what keeps http apps' real client IPs intact across the frp hop.
  Relayed DERP traffic never touches frp, nginx or serverone.
- **STUN (`999b`)**: clients send UDP 3478 directly to `vps-proxy`, answered
  by `derper-stun`. Packets keep their real client source IPs, which is what
  makes NAT traversal work.
- **Admission check**: for each DERP connection `derper-derp` POSTs the
  client's node public key to `https://headscale.polpetta.online/verify`
  (rides the control plane path above) and only relays for keys registered in
  the tailnet.

## Why the relay lives on the vps

frp forwards UDP by re-originating packets from the `frpc` container on
`serverone` (`10.0.1.131`) — there is no PROXY protocol equivalent for UDP.
When STUN answered through the tunnel, every client was told its public
endpoint was `10.0.1.131:<port>`, which breaks endpoint discovery. That is
why STUN moved to the vps (`derper-stun`, `stunonly` node `999b`).

With STUN gone from the tunnel, moving the relay too is the natural
completion: a relayed connection used to cross the frp tunnel *and* the home
WAN twice (in and out), adding latency and burning home uplink for traffic
that never touches a home machine. On the vps the relay terminates directly,
one TLS hop from the clients.

## Client admission (`/verify`)

`derper-derp` runs with `-verify-client-url=https://headscale.polpetta.online/verify`:

1. During the DERP handshake the client proves possession of its node private
   key (the `frameClientInfo` frame is a nacl box sealed to the server key)
   and presents its node public key.
2. derper POSTs `{NodePublic, Source}` to headscale's `/verify`, which
   answers `{"Allow": true}` iff that node key belongs to a registered node.
3. On `Allow: false` or non-200 the connection is rejected.

The endpoint is deliberately **fail-open** (derper's default): if headscale
is unreachable the relay keeps serving, admission is simply unverified for
that window. Set `-verify-client-url-fail-open=false` in derper-derp.nix to
prefer strictness instead.

`/verify` needs no auth: it only answers membership questions about keys the
connecting clients already proved, with a 4 KiB body cap.

## TLS certificates

Both DERP hostnames are covered by the wildcard `*.polpetta.online`
certificate issued by certbot on serverone (DNS-01 via Cloudflare). Renewals
are pushed to the vps automatically:

1. `certbot-renew.service` on serverone renews and reloads nginx as before,
   then fetches the private key copy from vps-proxy over ssh (as
   `billy@external.polpetta.online`, host key pinned in
   system/hosts/serverone/ssh.nix, key `derp-cert-sync-ssh-key` from sops),
   compares it locally against the fresh one and, if changed, scps both
   files into `/home/billy/derp-certs/`.
2. On vps-proxy a systemd path unit (`derper-derp-cert-sync.path`) watches
   the staging dir, checks the cert/key pair actually match, installs the
   files into `/var/lib/derper-derp/` and restarts the relay.

The push is gated on a local comparison of the fetched key, so the
unchanged-cert case (the timer runs every 12h) does not restart the relay;
the gate tracks the private key, which certbot regenerates on every renewal.
derper loads the certificate at
startup (`-certmode=manual`), so until a first push succeeds the
`derper-derp` service will stay in its restart loop.

## Operational notes

- `derper` requires a `-c <path>` config file: on first start it generates a
  private key and writes `{"PrivateKey": "privkey:..."}` there. Both services
  keep theirs in a `StateDirectory` (`/var/lib/derper/derper.conf`,
  `/var/lib/derper-derp/derper.conf`).
- The `derper-derp` HTTP listener (`-http-port -1`) is disabled; the relay is
  bound to 127.0.0.1:8443 (reachable only via the :443 demuxer), the port
  itself is firewall-closed. On the same vps, frps remotePort 8444
  (`nginx_https`) is deliberately not in the firewall either: frps binds
  remote ports on 0.0.0.0 (`proxyBindAddr` is global), the firewall is what
  keeps it loopback-only. `derper-stun`'s HTTP listener (`-a :8090`) is
  unused as well; clients only speak STUN on UDP 3478.
- Region code/name are `polpetta` / `Polpetta DERP` (they show up in client
  UIs); the region id stays 999.

## Testing

IMPORTANT: derper's STUN server only answers **tailscale-format** requests. A
probe must include the `SOFTWARE` attribute `"tailnode"` and a trailing
`FINGERPRINT` attribute (crc32 IEEE of the message XORed with `0x5354554e`).
Generic RFC 5389 STUN clients (e.g. `stun-client`, `pystun3`) will time out
**by design** — a timeout does not mean the server is broken.

For the same reason do not trust `tailscale netcheck` alone as proof that
STUN works: it may show the region as reachable via its HTTPS `/derp/probe`
fallback even when UDP STUN is dead.

Quick checks:

- `curl -v https://derp.polpetta.online/derp/probe` → 200 (hits the derper
  through the :443 demux path specifically).
- `openssl s_client -connect derp.polpetta.online:443 -servername
  derp.polpetta.online` → wildcard cert validates (TLS terminated by derper,
  demux is passthrough).
- `curl -o /dev/null -w '%{http_code}\n' https://headscale.polpetta.online/health`
  → 200 (full demux → frp → nginx path).
- `tailscale netcheck` on a client should list region 999 with both DERP and
  STUN (cross-check UDP with `tailscale debug netmap` latency or packet
  captures if in doubt).
- Restricted-network test (the point of running on 443): from a network that
  only allows standard ports, confirm DERP still relays — `tailscale debug
  derp 999` or a transfer forced through the relay.

## Deploy order

1. Create the DNS-only record `derp.polpetta.online` → `87.106.25.93`.
2. Generate the cert-sync ssh keypair: private key into the sops secrets for
   serverone as `derp-cert-sync-ssh-key`, public key into the nix-secrets
   repo as `public_keys/ssh/serverone_certsync.pub` (vps-proxy authorizes it
   for `billy`).
3. Deploy `vps-proxy` (relay + STUN + path unit come up; relay crashloops
   until the first cert push).
4. Deploy `serverone` (headscale starts advertising the new map, frpc stops
   forwarding STUN). Kick the first push with
   `sudo systemctl start certbot-renew.service` — the fetch comes back
   empty against the missing copy, so it always pushes on first run.

Rolling back means reverting both ends, same order (vps-proxy last).
