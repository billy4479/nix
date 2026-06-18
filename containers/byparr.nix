{ pkgs, ... }:
let
  name = "byparr";
  id = 134;
  uid = 5000 + id;
  uidString = toString uid;
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    inherit id;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        entrypoint = [ "${pkgs.byparr}/bin/byparr" ];
      };

      copyToRoot = [
        pkgs.byparr
        pkgs.coreutils
        pkgs.dockerTools.caCertificates
        (pkgs.writeTextDir "/etc/passwd" ''
          root:x:0:0:root:/root:/bin/sh
          container-${uidString}:x:${uidString}:5000:User for container ${name}:/var/empty:/bin/sh
          nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
        '')
        (pkgs.writeTextDir "/etc/group" ''
          root:x:0:
          containers:x:5000:
          nogroup:x:65534:
        '')
      ];
    };

    environment = {
      HOST = "0.0.0.0";
      PORT = "8191";
      HOME = "/tmp/byparr-home";
      BYPARR_CACHE_DIR = "/cache";
    };

    volumes = [
      {
        hostPath = "${baseSSDDir}/cache";
        containerPath = "/cache";
      }
    ];

  };
}
