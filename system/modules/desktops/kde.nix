{ pkgs, extraConfig, ... }: {
  services.xserver.enable = !extraConfig.wayland;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.defaultSession =
    if extraConfig.wayland
    then "plasma"
    else "plasmax11";
  services.desktopManager.plasma6.enable = true;

  xdg.portal = {
    enable = true;
    config.common.default = "kde";
    # https://wiki.archlinux.org/title/Cursor_themes#KDE_(Wayland)
    extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;
}
