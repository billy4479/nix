{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  # Lives under the historical `heascale` (sic) host path, see headscale.
  baseDir = "/mnt/SSD/apps/heascale";
in
{
  sops.secrets.headplane-env = lib.mkIf (options ? nerdctl-containers) { };

  polpetta.services.headplane = {
    container = {
      id = 16;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        name = "headplane";
        tag = "nix-local";

        copyToRoot = [
          pkgs.dockerTools.caCertificates
        ];

        config.entrypoint = [ (lib.getExe pkgs.headplane) ];
      };

      dependsOn = [ "headscale" ];

      environmentFiles = [ config.sops.secrets.headplane-env.path ];

      volumes = [
        {
          hostPath = "${./headplane.yaml}";
          containerPath = "/etc/headplane/config.yaml";
          readOnly = true;
        }
        {
          # headplane displays (and validates) headscale's configuration through
          # this mount; the file itself lives with the headscale service.
          hostPath = "${../headscale/headscale.yaml}";
          containerPath = "/etc/headscale/config.yaml";
          readOnly = true;
        }
        {
          hostPath = "${baseDir}/headplane";
          containerPath = "/var/lib/headplane";
        }
      ];
    };

    web = {
      port = 3000;
      access = "tailnet";
      # / answers 401; /admin is the login page.
      probe.path = "/admin";
    };
  };
}
