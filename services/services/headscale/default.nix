{
  pkgs,
  lib,
  options,
  ...
}:
let
  # The host path keeps a historical `heascale` typo; data lives there.
  baseDir = "/mnt/SSD/apps/heascale";
in
{
  # headscale forwards tailnet traffic into the nerdctl bridge (subnet router).
  boot.kernel.sysctl = lib.mkIf (options ? nerdctl-containers) {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  polpetta.services.headscale = {
    container = {
      id = 15;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        name = "headscale";
        tag = "nix-local";
        config = {
          Entrypoint = [ "/bin/headscale" ];
          Cmd = [ "serve" ];
        };

        copyToRoot = with pkgs; [
          headscale
          dockerTools.caCertificates
        ];
      };

      volumes = [
        {
          hostPath = "${baseDir}/lib";
          containerPath = "/var/lib/headscale";
        }
        {
          hostPath = "${baseDir}/run";
          containerPath = "/var/run/headscale";
        }
        {
          hostPath = "${./headscale.yaml}";
          containerPath = "/etc/headscale/config.yaml";
          readOnly = true;
        }
        {
          hostPath = "${./derp-custom.yaml}";
          containerPath = "/etc/headscale/derp-custom.yaml";
          readOnly = true;
        }
      ];
    };

    # Tailnet clients reach the control plane from the internet.
    web = {
      port = 8080;
      access = "public";
    };
  };
}
