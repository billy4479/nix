{
  pkgs,
  ...
}:
let
  name = "agent-up";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    id = 22;
    useNginx = true;

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
}
