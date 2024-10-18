{
  pkgs,
  lib,
  extraConfig,
  ...
}:
{
  imports = [ ./minecraft ];

  config = lib.mkIf extraConfig.games {
    home.packages = with pkgs; [ wineWow64Packages.staging ];

    programs.mangohud.enable = true;

    programs.minecraft = {
      enableClient = true;
      enableServer = true;
    };
  };
}
