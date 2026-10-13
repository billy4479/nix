{
  pkgs,
  config,
  ...
}:
let
  name = "bind9";
  id = 11;
  baseDir = "/mnt/SSD/apps/${name}";

  hosts = pkgs.callPackage ./hosts.nix { };
  bindConfig = pkgs.callPackage ./config.nix {
    bind9-hosts = hosts;
    generated-records = pkgs.writeText "generated-records.zone" config.polpetta.generated.bind9Records;
  };
  # Kept local (instead of reading config.nerdctl-containers / users.groups)
  # so this file stays evaluable on hosts without the containers module.
  # Must match containers/module.nix: uid = 5000 + id, gid = 5000.
  uid = toString (5000 + id);
  gid = "5000";
in
{
  polpetta.services.${name} = {
    container = {
      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";
        copyToRoot = [
          (pkgs.writeTextDir "/etc/passwd" ''
            bind:x:${uid}:${gid}:bind9 user:/var/empty:/run/current-system/sw/bin/nologin
          '')
          pkgs.dockerTools.binSh
        ];
        config.Entrypoint = [
          (pkgs.writeScript "bind9-entrypoint"
            # sh
            ''
              #!/bin/sh
              exec ${pkgs.bind}/bin/named -g -c /etc/bind/named.conf
            ''
          )
        ];
      };

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
        access = "local";
        probe.enable = true;
      }
      {
        port = 53;
        proto = "udp";
        access = "local";
      }
    ];
  };
}
