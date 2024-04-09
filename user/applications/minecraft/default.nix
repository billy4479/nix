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
  options.programs.minecraft = {
    enableClient = lib.mkEnableOption "Enable Minecraft Client";
    enableServer = lib.mkEnableOption "Enable Minecraft Server";
  };

  config = lib.mkIf extraConfig.games {
    home.packages =
      []
      ++ (
        if cfg.enableClient
        then [
          pkgs.prismlauncher
        ]
        else []
      )
      ++ (
        if cfg.enableServer
        then [
          extraPkgs.my-packages.server-tool

          # extraPkgs.my-packages.packwiz-installer # TODO: uncomment this once i figure out the grale build
          pkgs.packwiz

          # Yes, I use cloudflare tunnels to play minecraft
          pkgs.cloudflared
        ]
        else []
      );

    # Yeah, yeah, this is not plasma, but same config file format
    programs.plasma = lib.mkIf cfg.enableClient {
      enable = true;
      dataFile."PrismLauncher/prismlauncher.cfg"."General" = {
        # These are the options we need in order to skip the first run wizard
        "ApplicationTheme" = "system";
        "BackgroundCat" = "kitteh";
        "ConfigVersion" = "1.2";
        "IconTheme" = "pe_colored";
        "JavaPath" = "${pkgs.jdk17}/bin/java";
        "Language" = "en_US";
        "LastHostname" = "computerone";
        "MaxMemAlloc" = "4096";
        "MinMemAlloc" = "512";
        "ToolbarsLocked" = "false";
        "UseSystemLocale" = "true";

        # This is extra stuff I also like
        "ConsoleFont" = (import ../../fonts/names.nix).mono;
      };
    };
  };
}
