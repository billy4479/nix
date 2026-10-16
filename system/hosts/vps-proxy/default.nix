{
  flakeInputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./frp.nix
    ./sni-demux.nix
    ./derper-stun.nix
    ./derper-derp.nix
    ../../../services/module.nix

    # Imported for the frps projection only (public raw ports). Service files
    # gate everything container- or host-specific on nerdctl-containers, so
    # this evaluation is inert beyond polpetta.services.
    ../../../services/services/syncthing.nix
    ../../../services/services/bind9
    ../../../services/services/immich-server.nix
    ../../../services/services/immich-database.nix
    ../../../services/services/immich-ml.nix
    ../../../services/services/immich-redis.nix
    ../../../services/services/qbittorrent.nix
    ../../../services/services/radarr.nix
    ../../../services/services/jackett.nix
    ../../../services/services/sonarr.nix
    ../../../services/services/byparr.nix
    ../../../services/services/jellyfin.nix
    ../../../services/services/bentopdf.nix
    ../../../services/services/opencloud.nix
    ../../../services/services/searxng
    ../../../services/services/openchamber.nix
    ../../../services/services/mc-runner
    ../../../services/services/lunamultiplayer-server.nix
    ../../../services/services/calendar-proxy.nix
    ../../../services/services/ff.nix
    ../../../services/services/giuoco-del-divertimento.nix
    ../../../services/services/agent-up.nix
    ../../../services/services/grafana
    ../../../services/services/headscale
    ../../../services/services/headplane
  ];

  sops.secrets.user_password.neededForUsers = true;

  zramSwap.enable = true;
  services.smartd.enable = lib.mkForce false;

  users = {
    mutableUsers = false;
    users = {
      billy = {
        name = "billy";
        description = "Billy Panciotto";
        isNormalUser = true;
        uid = 1000;

        shell = pkgs.zsh;

        hashedPasswordFile = config.sops.secrets.user_password.path;
        openssh.authorizedKeys.keys = [
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_computerone.pub")
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_portatilo.pub")
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/openchamber.pub")
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/serverone_certsync.pub")
        ];

        extraGroups = [
          "wheel"
          "networkmanager"
        ];
      };
    };
  };

  networking = {
    hostName = "vps-proxy";
  };

  documentation.nixos.enable = false;
}
