{ ... }:
{
  imports = [
    ./modules/applications
    ./modules/cursor.nix
    ./modules/fonts
    ./modules/gtk.nix
    ./modules/gui.nix
    ./modules/services/syncthing.nix
    ./modules/xdg-open.nix

    ./modules/wallpapers.nix

    ./modules/desktops/qtile
    ./modules/qt.nix
  ];

  programs.ssh = {
    enable = true;

    matchBlocks = {
      serverone = {
        hostname = "100.105.236.47";
        forwardAgent = true;
      };
    };
  };
}
