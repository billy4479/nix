# SNI demuxer on TCP 443 (see docs/DERP.md): TLS passthrough for
# everything, routed by server name. DERP stays local, everything else is
# relayed to serverone's nginx over the wireguard tunnel — with a
# PROXY protocol v1 header so real client IPs survive the hop.
#
# The header must be written by the :443 dispatch block: that is the only
# stage whose $remote_addr is still the real client. A second hop across
# the tunnel would stamp the tunnel address into the header instead (nginx
# stream loses the original address across proxy_pass; verified on nginx
# 1.30.5). Since `proxy_protocol on` is per-server-block and derper is
# PP-unaware, the DERP branch rides a loopback hop whose `listen ...
# proxy_protocol` consumes (strips) the header before the relay on 8443.
{ domain, ... }:
{
  services.nginx = {
    enable = true;
    # Pure stream setup: no http vhosts (the module's default `localhost`
    # vhost would bind *:80, clashing with the DNAT of the edge forwards).
    virtualHosts = { };
    streamConfig = # nginx
      ''
        map $ssl_preread_server_name $sni443 {
          derp.${domain}  127.0.0.1:4441;
          default               10.0.1.6:4443;
        }

        server {              # dispatch: 443; PP carries the real client IP
          listen 443;
          ssl_preread on;
          proxy_protocol on;
          proxy_pass $sni443;
          proxy_timeout 1d;   # DERP/websockets are long-lived (default 10m)
        }

        server {              # strips the PP header before the (PP-unaware) derper
          listen 127.0.0.1:4441 proxy_protocol;
          proxy_pass 127.0.0.1:8443;
          proxy_timeout 1d;
        }
      '';
  };
}
