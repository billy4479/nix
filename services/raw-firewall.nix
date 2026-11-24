# Independent hooks run before the host firewall, after port-publishing DNAT.
# Same-bridge traffic does not have to traverse the inet forward chain.
{
  lib,
  services,
  nginxAddress ? null,
}:
let
  addressOf = svc: "10.0.1.${toString svc.container.id}";
  entries = lib.concatMap (
    svc:
    map (raw: {
      address = addressOf svc;
      inherit raw;
      isWebPort = svc.web != null && raw.proto == "tcp" && raw.port == svc.web.port;
    }) svc.raw
  ) (lib.attrValues services);
  sourcesOf =
    raw:
    if raw.allowedSources != null then
      raw.allowedSources
    else
      [
        "10.0.0.0/8"
        "192.168.0.0/16"
      ]
      ++ lib.optional (raw.access != "local") "100.64.0.0/10";
  matchPort = entry: "ip daddr ${entry.address} ${entry.raw.proto} dport ${toString entry.raw.port}";
  set = values: "{ ${lib.concatStringsSep ", " values} }";
  ingressRules =
    routed:
    lib.concatStringsSep "\n" (
      [ "ct state established,related return" ]
      ++ lib.concatMap (
        entry:
        lib.optional (routed && entry.raw.access == "public") ''iifname "wg0" ${matchPort entry} return''
        ++ lib.optional (sourcesOf entry.raw != [ ]) (
          if lib.elem "0.0.0.0/0" (sourcesOf entry.raw) then
            "${matchPort entry} return"
          else
            "${matchPort entry} ip saddr ${set (sourcesOf entry.raw)} return"
        )
      ) (lib.filter (entry: !entry.isWebPort) entries)
      ++ lib.concatMap (
        svc:
        lib.optional (
          svc.web != null && nginxAddress != null
        ) "ip saddr ${nginxAddress} ip daddr ${addressOf svc} tcp dport ${toString svc.web.port} return"
      ) (lib.attrValues services)
      ++ lib.optional (services != { }) "ip daddr ${set (map addressOf (lib.attrValues services))} drop"
    );
in
{
  ruleset = # nftables
    ''
      destroy table inet polpetta_raw
      destroy table bridge polpetta_raw
      table inet polpetta_raw {
        chain raw_ports {
          ${ingressRules true}
        }
        chain forward {
          type filter hook forward priority -10; policy accept;
          jump raw_ports
        }
      }
      table bridge polpetta_raw {
        chain forward {
          type filter hook forward priority -10; policy accept;
          ${ingressRules false}
        }
      }
    '';
}
