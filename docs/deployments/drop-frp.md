# Drop frp — wireguard tunnel + vps edge DNAT

This runbook replaces the frp tunnel with a kernel wireguard tunnel between
`serverone` and `vps-proxy`, with public ports DNAT'd on the vps edge and
source addresses preserved end to end (no SNAT). Real client IPs survive
without proxy protocol on raw ports; the web edge keeps its SNI demuxer and
proxy_protocol path, just across the tunnel instead of frps/frpc.

## How the new edge works

```
client ──► vps-proxy:443      SNI demuxer (local nginx stream; DERP stays local)
                              writes PROXY protocol, relays ──► wg ──► 10.0.1.6:4443
client ──► vps-proxy:80       DNAT ──► wg ──► 10.0.1.6:80 (plain, real IP)
client ──► vps-proxy:<port>   DNAT ──► wg ──► 10.0.1.<id>:<port> (raw entries)
```

Replies from the containers carry their bridge IP as source; on serverone a
conntrack mark (`-i wg0` → ctmark) is restored onto the replies
(`-i nerdctl0`), and a policy rule routes marked packets into a table whose
only route is the tunnel. On the vps, conntrack reverses the DNAT, so the
reply's source becomes the vps public IP again. `10.100.0.1` is the vps,
`10.100.0.2` is serverone; serverone initiates and keepalives (25 s), so the
home NAT needs no configuration and WAN IP changes heal automatically.

`vps-proxy:22` (ssh), `:443/tcp` (demuxer), `:3478/udp` (STUN) and `:51820/udp`
(tunnel) terminate locally; everything else that leaves the vps is a DNAT
rule from `polpetta.generated.dnatForwards` — the exposure is exactly the
public `raw` entries plus `:80`, same as the old frps `allowPorts` model.

## Stages

Each stage is one or two git commits, deployed in order. serverone is
deployed **before** the vps in stages 2 and 3.

| stage | commits | effect |
|-------|---------|--------|
| 0     | —       | secrets + preflight |
| 1     | `tunnel: add wireguard tunnel…` | tunnel comes up, nothing uses it |
| 2     | `edge: serve web vhosts through the tunnel` | web moves off frps |
| 3     | `edge: DNAT public raw ports through the tunnel, drop frp` | raw ports move, frp deleted |
| 4     | `edge: enable HTTP/3` (optional) | QUIC on udp/443 |
| 5     | `monitoring: probe the public edge` (optional) | dead tunnel alerts |

Rolling back = redeploying the previous commit on both hosts, in reverse
order (vps last). Until stage 3, frps is still running and owning the old
remote ports, so a stage-1/2 rollback is exact.

## Stage 0 — secrets and preflight

1. `vps-proxy.yaml` already has `wireguard-key`. Verify it matches
   `public_keys/wireguard/vps-proxy.pub` (derives the public key from the
   decrypted private one; the private key itself is never printed):

   ```sh
   cd /workspace/code/nix-secrets
   diff \
     <(direnv exec . sh -c 'sops -d --extract "[\"wireguard-key\"]" vps-proxy.yaml | wg pubkey') \
     public_keys/wireguard/vps-proxy.pub && echo ok
   ```

2. `serverone.yaml` has **no** `wireguard-key` yet. If you still have the
   private key belonging to `public_keys/wireguard/serverone.pub`, add it:

   ```sh
   direnv exec . sops serverone.yaml   # add: wireguard-key: <private key>
   ```

   Otherwise regenerate the pair (the nix config reads the `.pub` from the
   repo, so it picks the new key up automatically):

   ```sh
   nix shell nixpkgs#wireguard-tools -c sh -c \
     'wg genkey | tee serverone-wg.key | wg pubkey > public_keys/wireguard/serverone.pub'
   direnv exec . sops serverone.yaml   # add: wireguard-key: $(cat serverone-wg.key)
   rm serverone-wg.key
   git add public_keys/wireguard/serverone.pub serverone.yaml && git commit
   ```

3. Optional cleanup, after stage 3 is deployed everywhere: remove `frp-token`
   from both `serverone.yaml` and `vps-proxy.yaml`.

## Stage 1 — tunnel up

Deploy `serverone`, then `vps-proxy` (order irrelevant here, but the vps
last matches the later stages).

Verify:

```sh
ssh serverone  'sudo wg show wg0'        # handshake with 87.106.25.93, 25s keepalive
ssh vps-proxy 'sudo wg show wg0'         # peer endpoint = serverone's WAN
ssh serverone  'ip rule show'            # fwmark 0x1 lookup 51820 priority 10000
ssh serverone  'ip route show table 51820'
ssh serverone  'ip route get 1.1.1.1'    # default via the LAN uplink (unchanged)
ssh serverone  'ping -c1 10.100.0.1'     # tunnel round trip
```

Rollback: redeploy the previous generation; the tunnel disappearing is a
no-op at this point.

## Stage 2 — web cutover

Deploy **serverone first**, then `vps-proxy`.

Window note: once serverone trusts only `10.100.0.1`, frp-era connections
(no longer real_ip-restored) log the edge address on public vhosts until the
vps redeploys. ACLs stay correct throughout (that is what the explicit
`deny <edge>` line is for). Public web answers 401/redirects during the
seconds between the two deployments' `switch-to-configuration`.

Verify:

```sh
curl -o /dev/null -w '%{http_code}\n' https://headscale.polpetta.online/health   # 200
curl -o /dev/null -w '%{http_code}\n' https://calendar-proxy.polpetta.online     # 401
curl -o /dev/null -w '%{http_code}\n' https://derp.polpetta.online/derp/probe    # 200 (DERP unchanged)
curl -o /dev/null -w '%{http_code}\n' http://calendar-proxy.polpetta.online      # 301 → https
# from an external machine: real client IP in the 4443 vhost access log
ssh serverone 'nerdctl exec nginx tail -20 /dev/stdout' | grep calendar-proxy
# internal tier still denies internet sources (from an external machine):
curl -o /dev/null -w '%{http_code}\n' https://immich.internal.polpetta.online    # 403 (via public DNS wildcard → real IP denied)
```

Rollback: redeploy previous generations (serverone first, vps last) — frps
never stopped, so web lands back on it.

## Stage 3 — raw ports, frp removal

Deploy **serverone first** (frpc container disappears; its remote ports are
released when frps loses its client), then `vps-proxy` (frps deleted, DNAT
installed, firewall trimmed to `443/tcp`, `3478/udp`, `51820/udp`).

Between the two deployments raw ports (mc, bedrock, luna) are down; web is
not affected.

Verify:

```sh
# DNAT present on the vps:
ssh vps-proxy 'sudo iptables -t nat -S PREROUTING | grep DNAT'
# TCP (minecraft): real player IP visible in the server log / ss:
ssh serverone 'sudo ss -tn "sport = :25565"'   # peer = client public IP, not 10.0.1.x
# UDP (bedrock + luna) from an external client, then on serverone:
ssh serverone 'sudo conntrack -L -p udp | grep -E "19132|8800"'
# frp gone:
ssh vps-proxy 'systemctl is-active frp'        # inactive/unknown
ssh serverone 'sudo nerdctl ps -a | grep frp'  # empty
# web still fine (nginx real_ip anchor changed in stage 2 already)
```

Rollback: redeploy previous generations (vps first, serverone last) — frps
and frpc return, DNAT disappears.

## Stage 4 — HTTP/3 (optional)

Deploy both hosts (order irrelevant). Adds `udp/443 → 10.0.1.6:443` DNAT and
QUIC listeners + `Alt-Svc` on the vhosts; browsers only try h3 after seeing
Alt-Svc over the existing TCP path, so a broken QUIC path degrades to h2
silently.

Verify: `curl --http3-only -o /dev/null -w '%{http_code}\n'
https://calendar-proxy.polpetta.online` (needs a curl built with HTTP/3;
otherwise check `Alt-Svc: h3=":443"` in a browser devtools network panel).

Rollback: revert the commit (drop the udp DNAT; h2 continues to work).

## Stage 5 — edge probe (optional)

Deploy serverone. The `public-edge` blackbox target hairpins
serverone → vps → tunnel → nginx → calendar-proxy, so a dead tunnel, missing
DNAT or broken demuxer turns `probe_success{service="public-edge"}` off and
fires the existing probe alert. It cannot see which leg broke — check
`wg show` and the vps DNAT rules when it fires.

## Design notes (why it is built this way)

- **No SNAT anywhere.** Source preservation is what removes the frp userland
  relay *and* fixes real client IPs on raw ports (players no longer all share
  `10.0.1.131`). The price is policy routing on serverone: connmark-based,
  so ordinary container egress (downloads, updates) never rides the vps.
- **UDP game servers work unmodified.** Bedrock/Luna reply from the socket
  that received the packet; inside the container netns the only source
  address is the bridge IP, which is exactly what the vps conntrack expects.
- **`443/tcp` cannot be DNAT'd**: the demuxer and DERP terminate on the vps.
  The demuxer writes proxy_protocol at the only stage that still sees the
  real client IP; nginx on serverone restores it (`set_real_ip_from
  10.100.0.1`).
- **Strict rp_filter on the vps would kill replies**: after un-DNAT their
  source is the vps's own public IP when the route check runs.
  `checkReversePath = "loose"` is pinned on the vps; serverone already sets
  it for tailscale.
- **MSS clamping** on the vps (PMTU 1420 in the tunnel vs 1500 WAN) keeps TCP
  bulk flows from stalling; QUIC (stage 4) does its own PMTU discovery.
