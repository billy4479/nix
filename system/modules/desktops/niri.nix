{ pkgs, ... }:
{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  xdg.portal = {
    enable = true;

    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];

    config.niri = {
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
  };

  services.displayManager.defaultSession = "niri";
}
