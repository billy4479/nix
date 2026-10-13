{ pkgs, ... }:
let
  name = "agent-up";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  polpetta.services.${name} = {
    container = {
      id = 22;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          agent-up-server
        ];

        config.entrypoint = [
          "/bin/agent-up-server"
        ];
      };

      volumes = [
        {
          hostPath = baseSSDDir;
          containerPath = "/data";
        }
      ];

      environment = {
        AGENTUP_LISTEN = ":3000";
        AGENTUP_DATA_DIR = "/data";
        AGENTUP_MAX_UPLOAD_SIZE = "10485760"; # 10 MiB
        AGENTUP_UPLOAD_TTL = "${toString (30 * 24)}h";
      };
    };

    web = {
      port = 3000;
      access = "tailnet";
      # Answers 404 on /; still proves the server is alive.
      probe.unauth = true;
      nginx.extraConfig = ''
        client_max_body_size 10M;
      '';
    };
  };
}
