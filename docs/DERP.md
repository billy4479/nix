# DERP / STUN architecture

This document describes how the tailnet's DERP region `999` is wired up and why
the DERP relay and the STUN server live on different machines.

## Region layout

Headscale (v0.29.3) runs in a `nerdctl` container on `serverone` (container id
15, IP `10.0.1.15`) with its embedded DERP server enabled. The region it
advertises is hand written in `../containers/headscale/derp-custom.yaml`
(mounted in the container at `/etc/headscale/derp-custom.yaml` and referenced
by `derp.paths` in `config.yaml`):

| Node  | Role        | Hostname                    | IPv4          | Ports              |
|-------|-------------|-----------------------------|---------------|--------------------|
| `999a`| DERP relay  | `headscale.polpetta.online` | `87.106.25.93`| TCP 443, STUN off (`stunport: -1`) |
| `999b`| STUN only   | `headscale.polpetta.online` | `87.106.25.93`| UDP 3478 (`stunonly: true`) |

Both nodes point at `vps-proxy` (public IP `87.106.25.93`).

## Traffic flows

- **Control plane**: clients → `headscale.polpetta.online` → `frps` on
  `vps-proxy` → frp tunnel → `frpc` on `serverone` → nginx container (10.0.1.6,
  `:81`/`:4443` with PROXY protocol) → headscale `:8080` (container
  `10.0.1.15`). Unchanged by the split.
- **DERP relay (`999a`)**: same TCP 443 path as the control plane, terminated by
  the embedded DERP server in the headscale container. Unchanged by the split.
- **STUN (`999b`)**: clients send UDP 3478 **directly** to `vps-proxy`, where
  the `derper-stun` systemd service (a STUN-only `derper`) answers. Packets
  never traverse frp, so they keep the real client source IPs.

## Why STUN had to move

frp forwards UDP by re-originating packets from the `frpc` container on
`serverone` (`10.0.1.131`) — there is no PROXY protocol equivalent for UDP.
When the embedded STUN server answered through the tunnel, it reflected the
packet's apparent source address, so **every tailnet client was told its public
endpoint was `10.0.1.131:<port>`**, which breaks NAT traversal / endpoint
discovery.

Tailscale's `DERPNode` semantics used to solve this:

- `stunport: -1`: clients never send STUN to this node (used on `999a`, the
  relay, which only handles TCP).
- `stunonly: true`: the node is only used for STUN, it is not treated as a
  reachable DERP relay (used on `999b`).

Since `derp.server.automatically_add_embedded_derp_region` is `false`,
headscale does not generate its own region entry and the map from `derp.paths`
is the only source — that's why the hand written file must list the relay node
explicitly.

## Operational notes

- Headscale still **requires and runs** its embedded STUN listener
  (`derp.server.stun_listen_addr` must be non-empty when the embedded DERP
  server is enabled); it is simply no longer advertised to clients.
- `derper` requires a `-c <path>` config file: on first start it generates a
  private key and writes `{"PrivateKey": "privkey:..."}` there. The service uses
  `StateDirectory=derper` (`/var/lib/derper/derper.conf`).
- The `derper-stun` HTTP listener (`-a :8090`, plain HTTP, `-http-port -1`) is
  unused; TCP 8090 is intentionally **not** open in the firewall, clients only
  STUN UDP 3478.

## Testing

IMPORTANT: headscale's and derper's STUN servers only answer
**tailscale-format** requests. A probe must include the `SOFTWARE` attribute
`"tailnode"` and a trailing `FINGERPRINT` attribute (crc32 IEEE of the message
XORed with `0x5354554e`). Generic RFC 5389 STUN clients (e.g. `stun-client`,
`pystun3`) will time out **by design** — a timeout does not mean the server is
broken.

For the same reason do not trust `tailscale netcheck` alone as proof that STUN
works: it may show the region as reachable via its HTTPS `/derp/probe`
fallback even when UDP STUN is dead.

## Deploy order

Deploy `vps-proxy` first (so STUN is already served there and frps has released
UDP 3478), then `serverone` (so headscale starts advertising the new map and
frpc stops forwarding STUN). Rolling back means reverting both ends.
