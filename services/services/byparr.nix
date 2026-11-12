{ pkgs, lib, ... }:
let
  name = "byparr";
  id = 134;
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  polpetta.services.byparr = {
    container = {
      inherit id;

      entrypoint = [
        (pkgs.writeShellScript "byparr-entrypoint" # sh
          ''
            export PATH=${
              lib.makeBinPath [
                pkgs.xkbcomp
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

      copyToRoot = [
        pkgs.byparr
        pkgs.fontconfig
        pkgs.noto-fonts
        pkgs.xvfb
      ];

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

      # Chromium temp files plus one leftover zip per solved request add up
      # (~600MB over a week); tmpfs is wiped on restart, this bounds it until
      # then so solves fail loudly instead of eating RAM.
      tmpfs = [ "/tmp:size=1g" ];
    };

    web = {
      port = 8191;
      access = "tailnet";

      # / redirects to /docs, which stays 200 even when the browser driver is
      # dead and every solve 500s; /health actually reflects app health.
      probe.path = "/health";
      # /health checks the browser driver by driving it through a real
      # google.com page load, so even a healthy answer takes 4-6.5s and
      # bursts past the probe timeout flapped ContainerDown in the evening
      # hours when jackett and mircrewrr solve more. 5m makes the probe
      # alert only when the browser is truly gone.
      probe.timeout = "5m";
    };
  };
}
