{ pkgs, lib, ... }:
let
  baseHDDDir = "/mnt/HDD/apps/immich";
in
{
  polpetta.services.immich-ml = {
    web = {
      port = 3003;
      access = "local";
      allowedSources = [ "10.0.1.3/32" ];
      probe.enable = false;
      nginx.extraConfig = ''
        client_max_body_size 0;
        proxy_request_buffering off;
        proxy_read_timeout 600s;
      '';
    };

    container = {
      id = 128;
      entrypoint = [ (lib.getExe pkgs.immich-machine-learning) ];
      volumes = [
        {
          hostPath = "${baseHDDDir}/model-cache";
          containerPath = "/cache";
        }
      ];
      environment = {
        MACHINE_LEARNING_CACHE_FOLDER = "/cache";

        HF_HOME = "/cache/hf";
        HF_HUB_CACHE = "/cache/hf/hub";
        HF_XET_CACHE = "/cache/hf/xet";

        MPLCONFIGDIR = "/cache/matplotlib";
      };
    };
  };
}
