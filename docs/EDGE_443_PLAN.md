# Plan: DERP relay on 443 behind an SNI demuxer (vps-proxy)

## Goal

Serve `derp.polpetta.online` on **TCP 443** so the relay works from networks that
only allow standard ports. An **SNI demuxer** on vps-proxy:443 (TLS passthrough)
routes by server name: DERP stays local, everything else keeps flowing through
**frp** to serverone's nginx. Real client IPs are preserved for http apps via
PROXY protocol.

## Traffic, current vs target

```
CURRENT
  :443  → frps(remotePort 443) ──frp──▶ frpc ─▶ nginx:4443  (PPv2 written by frpc)
  :8443 → derper-derp (manual TLS certs pushed from serverone)
  :80   → frps ──frp──▶ frpc ─▶ nginx:81 (PPv2)
  :3478/udp → derper-stun          (untouched)
  :25565/tcp :8800/udp :19132/udp → frp   (untouched)

TARGET
  :443 → sni-demux (nginx stream, ssl_preread, passthrough)
     ├─ SNI derp.polpetta.online ─▶ 127.0.0.1:8443 derper (no PP)
     └─ default ────────────────▶ 127.0.0.1:4441 ─▶ 127.0.0.1:8444 frps
                                     ──frp──▶ frpc ─▶ nginx:4443 (PP v1 from demuxer)
  :8443 firewall-closed, derper bound to 127.0.0.1 only
```

## Key mechanism: real client IPs through frp

Verified against frp source (frps has no PROXY-protocol parsing;
`transport.proxyProtocolVersion` only controls a header **frpc generates** from
the peer address frps observed):

- If the demuxer sent PP **and** frpc kept `proxyProtocolVersion = "v2"`, nginx
  would receive two headers (frpc's first, src=127.0.0.1) and treat the
  demuxer's header as payload → broken.
- Therefore: the **demuxer writes PP**, and `transport.proxyProtocolVersion` is
  **removed** from the `nginx_https` proxy. The header transits frps/frpc
  byte-for-byte; nginx's `listen 4443 ssl proxy_protocol` and
  `set_real_ip_from 10.0.1.131` parse it unchanged. The port-80 path keeps its
  frps-generated PPv2 (frps still sees the real peer there).

PP version note: nixpkgs nginx 1.30.5 stream `proxy_protocol on` emits **v1
only** (v2 needs mainline ≥ 1.31.4). nginx parses both → v1 is fine.

## Changes by file

1. `system/hosts/vps-proxy/frp.nix` — `allowPorts`: 443 → 8444.
2. **New** `system/hosts/vps-proxy/sni-demux.nix` — `services.nginx` with
   `streamConfig`:

   ```nginx
   stream {
     map $ssl_preread_server_name $sni443 {
       derp.polpetta.online  127.0.0.1:8443;
       default               127.0.0.1:4441;
     }
     server {                     # dispatch: 443
       listen 443;
       ssl_preread on;
       proxy_pass $sni443;
       proxy_timeout 1d;          # DERP/websockets are long-lived (default 10m)
     }
     server {                     # → frps, PP carries the real client IP
       listen 127.0.0.1:4441;
       proxy_pass 127.0.0.1:8444;
       proxy_protocol on;
       proxy_timeout 1d;
     }
   }
   ```

   Why only one loopback stage: `proxy_protocol on` is a per-server-block
   directive, and the frps hop must get a PP header while the raw :443
   listener must stay passthrough. derper is not PP-aware and needs no
   header, so the map routes it straight to 127.0.0.1:8443 — no intermediate
   stage for the DERP path.
3. `system/hosts/vps-proxy/derper-derp.nix` — `-a 127.0.0.1:8443`; drop 8443
   from `allowedTCPPorts`; update comments. (The all-interfaces bind constraint
   only exists on derper-stun because STUN inherits the bind IP.)
4. `containers/frp.nix` (serverone) — `nginx_https`: `remotePort = 8444`,
   remove `transport.proxyProtocolVersion`. `nginx_http` and the game tunnels
   untouched.
5. `containers/headscale/derp-custom.yaml` — `derpport: 443` + comment updates.
6. `containers/nginx/config/nginx.conf` — **no changes**: `listen 4443 ssl
   proxy_protocol` already accepts PP v1/v2, `set_real_ip_from 10.0.1.131`
   still correct (the header's TCP peer is still the frpc container). The
   `*.internal` vhost on `:4443` keeps shielding internal apps from internet
   clients, now with their real address restored from the demuxer's PP header.
7. `docs/DERP.md` — port table (8443 → 443), verification commands, firewall
   notes.

## Firewall delta (vps-proxy)

- 443: stays open (now the demuxer).
- 8443: **removed** (derper is loopback-only).
- 8444: deliberately **not** opened. frps binds remote ports on `0.0.0.0`
  (`proxyBindAddr` is global and would hide minecraft/luna from the internet),
  so the firewall is what keeps 8444 loopback-only for the demuxer.

## Cutover (one commit, deploy order matters)

1. (User, anytime) Delete the stale `derp.polpetta.online` AAAA record (points
   at GitHub Pages; the vps has no IPv6 — v6 clients never reached the vps
   anyway).
2. Deploy **vps-proxy**: frps frees 443 / allows 8444; demuxer binds 443 → DERP
   is reachable on :443 immediately. `nginx_https` is down until step 3 (http
   apps on 443 fail for the whole window). The window is accepted
   indefinitely: there is no timeout or automatic rollback trigger, it simply
   lasts until serverone is deployed.
3. Deploy **serverone**: frpc re-registers `nginx_https` on 8444 (frp retries
   automatically; the container recreate also bounces the game tunnels for a
   few seconds); headscale serves the new DERP map.
4. Clients refresh the map → DERP on 443. Clients still on the old map fail on
   8443 until refresh (immediate close was chosen over a grace period).

Rollback: `git revert`, then redeploy both hosts back-to-back — either
single-host order leaves a partial window (vps-proxy alone: frps re-allows 443
but `nginx_https` still registers 8444; serverone alone: frpc registers 443
against an frps that no longer allows it). DERP clients holding the new map
blip until headscale pushes the old map again; they self-heal on refresh.

## Verification

- `curl -o /dev/null -w '%{http_code}\n'
  https://derp.polpetta.online/derp/probe` → 200. This hits the derper
  through the new :443 demux path specifically.
- Restricted-network test (the point of the change): from a network that
  only allows standard ports (e.g. a phone hotspot with a firewall rule
  blocking 8443), confirm DERP still relays — `tailscale debug derp 999` or
  a file transfer forced through the relay.
- `openssl s_client -connect derp.polpetta.online:443 -servername
  derp.polpetta.online` → wildcard `polpetta.online` cert validates (TLS
  terminated by derper, demux is passthrough).
- `curl -o /dev/null -w '%{http_code}\n'
  https://derp.polpetta.online/generate_204` → 204.
- `curl -o /dev/null -w '%{http_code}\n'
  https://headscale.polpetta.online/health` → 200 (full demux → frp → nginx
  path).
- Real IP: from an external network, hit a public vhost; serverone nginx
  access log must show the public IP (not `127.0.0.1`) for the 4443 vhost.
- `tailscale netcheck` on a tailnet client → region 999 reachable (secondary
  signal only: docs/DERP.md warns netcheck can pass via its HTTPS probe
  fallback even when the real path is broken).
