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

    ./modules/desktops/kde
  ];
}