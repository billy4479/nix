# Independent nft hooks run before CNI's iptables ACCEPT rules. The bridge
# family also covers peer-to-peer traffic without depending on br_netfilter.
{ lib, services }:
let
  entries = lib.concatMap (
    name:
    map (raw: {
      address = "10.0.1.${toString services.${name}.container.id}";
      inherit raw;
    }) services.${name}.raw
  ) (lib.attrNames services);
  restricted = lib.filter (
    entry: entry.raw.access != "public" || entry.raw.allowedSources != null
  ) entries;
  policy = map (entry: {
    inherit (entry) address;
    inherit (entry.raw) proto port;
    sources = lib.unique (
      [ "10.0.1.1/32" ]
      ++ (
        if entry.raw.allowedSources != null then
          entry.raw.allowedSources
        else
          [
            "10.0.0.0/8"
            "192.168.0.0/16"
          ]
          ++ lib.optional (entry.raw.access == "tailnet") "100.64.0.0/10"
      )
    );
  }) restricted;
  rules = lib.concatMapStringsSep "\n" (
    entry:
    let
      match = "ip daddr ${entry.address} ${entry.proto} dport ${toString entry.port}";
    in
    "${match} ip saddr != { ${lib.concatStringsSep ", " entry.sources} } drop"
  ) policy;
in
{
  inherit policy;
  ruleset = # nftables
    ''
      destroy table inet polpetta_raw
      destroy table bridge polpetta_raw
      table inet polpetta_raw {
        chain raw_ports {
          ${rules}
        }
        chain forward {
          type filter hook forward priority -10; policy accept;
          jump raw_ports
        }
        chain output {
          type filter hook output priority -10; policy accept;
          jump raw_ports
        }
      }
      table bridge polpetta_raw {
        chain forward {
          type filter hook forward priority -10; policy accept;
          ${rules}
        }
      }
    '';
}
