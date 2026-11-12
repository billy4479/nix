{
  pkgs,
  domain,
  config,
  ...
}:
let
  name = "bind9";
  id = 11;
  baseDir = "/mnt/SSD/apps/${name}";

  hosts = pkgs.callPackage ./hosts.nix { };
  bindConfig = pkgs.callPackage ./config.nix {
    inherit domain;
    bind9-hosts = hosts;
    generated-records = pkgs.writeText "generated-records.zone" config.polpetta.generated.bind9Records;
  };
in
{
  polpetta.services.${name} = {
    container = {
      userName = "bind";
      entrypoint = [
        (pkgs.writeScript "bind9-entrypoint"
          # sh
          ''
            #!/bin/sh
            exec ${pkgs.bind}/bin/named -g -c /etc/bind/named.conf
          ''
        )
      ];

      inherit id;
      capabilities = [ "CAP_NET_BIND_SERVICE" ];
      dns = null;

      volumes = [
        {
          hostPath = "${baseDir}/cache";
          containerPath = "/var/cache/bind";
        }
        {
          hostPath = "${baseDir}/lib";
          containerPath = "/var/lib/bind";
        }
        {
          hostPath = "${baseDir}/log";
          containerPath = "/var/log";
        }
        {
          hostPath = "${bindConfig}";
          containerPath = "/etc/bind";
          readOnly = true;
        }
      ];

      ports = [
        "53:53/tcp"
        "53:53/udp"
      ];
    };

    # DNS is declared like any other port so it can be probed; it stays
    # private (not tunneled). Only the tcp listener has a probe.
    raw = [
      {
        port = 53;
        proto = "tcp";
        access = "tailnet";
        probe.enable = true;
      }
      {
        port = 53;
        proto = "udp";
        access = "tailnet";
      }
    ];
  };
}
