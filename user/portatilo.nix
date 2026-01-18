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

    ./modules/desktops
  ];

  programs.ssh = {
    enable = true;

    matchBlocks = {
      serverone = {
        hostname = "10.0.0.1";
        forwardAgent = true;
        addKeysToAgent = "yes";
      };
      vps-proxy = {
        hostname = "87.106.25.93";
        forwardAgent = true;
        addKeysToAgent = "yes";
      };
    };
  };
}
