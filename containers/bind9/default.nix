{
  pkgs,
  config,
  ...
}:
let
  name = "bind9";
  baseDir = "/mnt/SSD/apps/${name}";

  hosts = pkgs.callPackage ./hosts.nix { };
  bindConfig = pkgs.callPackage ./config.nix { bind9-hosts = hosts; };
  uid = toString config.users.users."container-${name}".uid;
  gid = toString config.users.groups.containers.gid;
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      name = "bind9";
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
            exec ${pkgs.bind}/bin/named -u bind -g -c /etc/bind/named.conf
          ''
        )
      ];
    };

    id = 11;
    runByUser = false; # Bind apparently _expects_ to be run as root
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
}
