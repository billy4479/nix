{ pkgs, lib, ... }:
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
    useNginx = true;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        entrypoint = [
          (pkgs.writeShellScript "byparr-entrypoint" # sh
            ''
              export PATH=${
                lib.makeBinPath [
                  pkgs.xorg.xkbcomp
                  pkgs.coreutils
                ]
              }
              mkdir -p /tmp/.X11-unix
              chmod 1777 /tmp/.X11-unix
              ${pkgs.xvfb}/bin/Xvfb :99 \
                -screen 0 1920x1080x24 \
                -xkbdir ${pkgs.xkeyboard_config}/share/X11/xkb &
              xvfbPid=$!
              until [ -S /tmp/.X11-unix/X99 ]; do
                kill -0 "$xvfbPid" 2>/dev/null || exit 1
                sleep 0.1
              done
              exec ${lib.getExe pkgs.byparr}
            ''
          )
        ];
      };

      copyToRoot = [
        pkgs.byparr
        pkgs.coreutils
        pkgs.dockerTools.binSh
        pkgs.dockerTools.caCertificates
        pkgs.fontconfig
        pkgs.noto-fonts
        pkgs.xvfb
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
      DISPLAY = ":99";
      FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
    };

    volumes = [
      {
        hostPath = "${baseSSDDir}/cache";
        containerPath = "/cache";
      }
    ];

  };
}
