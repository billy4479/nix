{
  pkgs,
  lib,
  domain,
  config,
  ...
}:
let
  name = "bind9";
  id = 11;
  baseDir = "/mnt/SSD/apps/${name}";

  inherit (config.polpetta.generated) adminDnsRecords adminIngress agentPreview;
  hosts = pkgs.callPackage ./hosts.nix { };
  bindConfig = pkgs.callPackage ./config.nix {
    inherit domain;
    bind9-hosts = hosts;
    admin-records = pkgs.writeText "admin-records.zone" (
      adminDnsRecords
      + lib.optionalString agentPreview.enable ''
        ${agentPreview.hostname}. IN A ${adminIngress.address}
        *.${agentPreview.hostname}. IN A ${adminIngress.address}
      ''
    );
    legacy-admin-records = pkgs.writeText "legacy-admin-records.zone" config.polpetta.generated.legacyAdminDnsRecords;
    generated-records = pkgs.writeText "generated-records.zone" config.polpetta.generated.bind9Records;
  };
in
{
  polpetta.services.${name} = {
    container = {
      userName = "bind";
      entrypoint = [ "${pkgs.bind}/bin/named" ];
      cmd = [
        "-g"
        "-c"
        "/etc/bind/named.conf"
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
          isCache = true;
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
