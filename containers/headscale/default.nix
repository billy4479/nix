{
  pkgs,
  config,
  ...
}:
let
  name = "heascale";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  networking.firewall.allowedUDPPorts = [ 51820 ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  sops.secrets.headplane-env = { };

  nerdctl-containers = {
    headscale = {
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
          userAccessible = true;
        }
        {
          hostPath = "${baseDir}/run";
          containerPath = "/var/run/headscale";
          userAccessible = true;
        }
        {
          hostPath = "${./headscale.yaml}";
          containerPath = "/etc/headscale/config.yaml";
          readOnly = true;
        }
      ];
    };

    headplane = {
      id = 16;
      imageToPull = "ghcr.io/tale/headplane";
      dependsOn = [ "headscale" ];
      environmentFiles = [ config.sops.secrets.headplane-env.path ];
      volumes = [
        {
          hostPath = "${./headplane.yaml}";
          containerPath = "/etc/headplane/config.yaml";
          readOnly = true;
        }
        {
          hostPath = "${./headscale.yaml}";
          containerPath = "/etc/headscale/config.yaml";
          readOnly = true;
        }
        {
          hostPath = "${baseDir}/headplane";
          containerPath = "/var/lib/headplane";
        }
      ];
    };
  };
}
