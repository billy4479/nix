{ pkgs, extraConfig, ... }:
assert (extraConfig.wayland);
{
  programs.niri.enable = true;

  xdg.portal = {
    enable = true;
    config.niri = {
      default = [
        "gtk"
        "gnome"
      ];
      "org.freedesktop.impl.portal.Secret" = [
        "gnome-keyring"
      ];
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
    };

    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
      gnome-keyring
    ];
  };

  services.displayManager.defaultSession = "niri";
}
