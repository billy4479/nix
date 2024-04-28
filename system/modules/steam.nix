{
  pkgs,
  lib,
  extraPkgs,
  extraConfig,
  config,
  ...
}: let
  cfg = config.programs.minecraft;
in {
  # TODO: this should be in home manager...
  config = lib.mkIf extraConfig.games {
    # https://nixos.wiki/wiki/Steam
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
  };
}
