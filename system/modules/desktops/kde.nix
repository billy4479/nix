{extraConfig, ...}: {
  services.xserver.enable = !extraConfig.wayland;

  # Enable the KDE Plasma Desktop Environment.
  services.xserver.displayManager.defaultSession =
    if extraConfig.wayland
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
