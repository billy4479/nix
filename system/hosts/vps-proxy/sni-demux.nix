# SNI demuxer on TCP 443 (see docs/EDGE_443_PLAN.md): TLS passthrough for
# everything, routed by server name. DERP stays local, everything else goes
# to frps (remotePort 8444) which tunnels it to serverone's nginx — with a
# PROXY protocol v1 header so real client IPs survive the frp hop.
#
# Only one loopback stage exists: `proxy_protocol on` is per-server-block,
# and the frps hop must get a header while the raw :443 listener must stay
# passthrough. derper is not PP-aware and needs no header, so the map sends
# it straight to 127.0.0.1:8443.
{ ... }:
{
  services.nginx = {
    enable = true;
    # Pure stream setup: no http vhosts (the module's default `localhost`
    # vhost would bind *:80, clashing with frps remotePort 80).
    virtualHosts = { };
    streamConfig = # nginx
      ''
        map $ssl_preread_server_name $sni443 {
          derp.polpetta.online  127.0.0.1:8443;
          default               127.0.0.1:4441;
        }

        server {              # dispatch: 443
          listen 443;
          ssl_preread on;
          proxy_pass $sni443;
          proxy_timeout 1d;   # DERP/websockets are long-lived (default 10m)
        }

        server {              # → frps; PP carries the real client IP
          listen 127.0.0.1:4441;
          proxy_pass 127.0.0.1:8444;
          proxy_protocol on;
          proxy_timeout 1d;
        }
      '';
  };
}
