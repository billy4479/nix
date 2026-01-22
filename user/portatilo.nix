{ ... }:
{
  imports = [
    ./modules/applications
    ./modules/cursor.nix
    ./modules/fonts
    ./modules/gtk.nix
    ./modules/gui.nix
    ./modules/services/syncthing.nix
    ./modules/ssh.nix
    ./modules/xdg-open.nix

    ./modules/wallpapers.nix

    ./modules/desktops
    ./modules/scripts
  ];
}
