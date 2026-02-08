{ pkgs, lib, ... }:
let
  name = "flaresolverr";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  # https://chatgpt.com/share/e/6966ac17-7d2c-8014-9a54-ab1ca711c179
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        Env = [
          "HOME=/app"
          "XDG_CACHE_HOME=/tmp"
          "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
        ];
        EntryPoint = [
          (pkgs.writeShellScript "entrypoint.sh" ''
            set -e
            mkdir -p /tmp/.X11-unix
            chmod 1777 /tmp/.X11-unix
            exec ${lib.getExe pkgs.flaresolverr}
          '')
        ];
        WorkingDir = "/app";
      };

      copyToRoot = with pkgs; [
        dockerTools.caCertificates

        xorg.xvfb
        coreutils
        fontconfig
        noto-fonts
      ];
    };
    id = 133;

    environment = {
      "LOG_LEVEL" = "debug";
    };

    volumes = [
      {
        hostPath = "${baseSSDDir}";
        containerPath = "/app";
      }
    ];

    # Aggressive stop timeout, otherwise it takes forever
    stopTimeout = "2s";
  };
}
