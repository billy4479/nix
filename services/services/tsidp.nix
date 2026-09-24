{
  pkgs,
  config,
  lib,
  options,
  ...
}:
let
  name = "tsidp";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    tsidp-authkey.key = "tsidp/authkey";
  };

  sops.templates."tsidp-env" = lib.mkIf (options ? nerdctl-containers) {
    content = # sh
      ''
        TS_AUTHKEY=${config.sops.placeholder.tsidp-authkey}
      '';
    restartUnits = [ "nerdctl-${name}.service" ];
  };

  polpetta.services.${name} = {
    container = {
      id = 25;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          tsidp
          dockerTools.caCertificates
        ];

        config = {
          Entrypoint = [ "/bin/tsidp" ];
        };
      };

      cmd = [
        "-dir"
        "/var/lib/tsidp"
        "-listen"
        "0.0.0.0:8080"
        "-trusted-proxy"
        "10.0.1.6"
        "-server-url"
        "https://idp.internal.polpetta.online"
        "-advertise-tags"
        "tag:idp"
      ];

      environment = {
        TS_CONTROL_URL = "https://headscale.polpetta.online:443";
        TS_HOSTNAME = "idp";
        TAILSCALE_USE_WIP_CODE = "1";
        TSIDP_LOG = "info";
      };

      environmentFiles = [ config.sops.templates."tsidp-env".path ];

      volumes = [
        {
          hostPath = "${baseDir}/lib";
          containerPath = "/var/lib/tsidp";
        }
      ];
    };

    web = {
      port = 8080;
      access = "tailnet";
      # The service name would generate tsidp.internal...; the relying
      # parties (and the sops-seeded clients) know it as idp.
      domain = "idp.internal.polpetta.online";
    };
  };
}
