# Independent hooks run before the host firewall, after port-publishing DNAT.
# Same-bridge traffic does not have to traverse the inet forward chain.
{
  lib,
  services,
  nginxAddress ? null,
  adminIngress ? null,
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
  hasAdminListener = adminIngress != null && nginxAddress != null;
  adminEnabled = hasAdminListener && adminIngress.enable;
  adminListener = "ip daddr ${nginxAddress} tcp dport ${toString adminIngress.port}";
  ingressRules =
    routed:
    lib.concatStringsSep "\n" (
      lib.optionals hasAdminListener (
        lib.optional (routed && adminEnabled)
          ''iifname "tailscale0" ip saddr 100.64.0.0/10 ${adminListener} ct status dnat ct original ip daddr ${adminIngress.address} ct original proto-dst 443 return''
        # Routed traffic passed the check above. On a plain bridge frame,
        # never trust a source IP to authorize direct use of this listener.
        ++ lib.optional routed "${adminListener} drop"
      )
      ++ [ "ct state established,related return" ]
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
        let
          web = svc.web;
          proxy = lib.optional (
            nginxAddress != null && (!routed || (web.access or null) != "admin-only")
          ) nginxAddress;
          clients = map (name: addressOf services.${name}) (web.integrationClients or [ ]);
          sources = proxy ++ lib.optionals (!routed) clients;
        in
        lib.optional (
          web != null && sources != [ ]
        ) "ip saddr ${set sources} ip daddr ${addressOf svc} tcp dport ${toString web.port} return"
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
        ${lib.optionalString hasAdminListener ''
          chain admin_prerouting {
            type nat hook prerouting priority dstnat - 5; policy accept;
            ${lib.optionalString adminEnabled ''
              iifname "tailscale0" ip saddr 100.64.0.0/10 ip daddr ${adminIngress.address} tcp dport 443 dnat ip to ${nginxAddress}:${toString adminIngress.port}
            ''}
          }
          chain admin_no_fallback {
            type filter hook prerouting priority dstnat + 5; policy accept;
            ip daddr ${adminIngress.address} drop
          }
        ''}
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
          ${lib.optionalString hasAdminListener "${adminListener} drop"}
          ${ingressRules false}
        }
      }
    '';
}
