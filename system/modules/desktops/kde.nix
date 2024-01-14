{wayland, ...}: {
  services.xserver.enable = !wayland;

  # Enable the KDE Plasma Desktop Environment.
  services.xserver.displayManager.defaultSession =
    if wayland
    then "plasmawayland"
    else "plasma";
  services.xserver.desktopManager.plasma5.enable = true;

  xdg.portal = {
    enable = true;
    config.common.default = "kde";
    # extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;
}
