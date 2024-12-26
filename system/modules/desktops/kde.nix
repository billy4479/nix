{ pkgs, extraConfig, ... }:
{
  services.xserver.enable = !extraConfig.wayland;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.defaultSession = if extraConfig.wayland then "plasma" else "plasmax11";
  services.desktopManager.plasma6 = {
    enable = true;
  };
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    elisa # Fucking useless
  ];

  xdg.portal = {
    enable = true;
    config.common.default = "kde";
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;
}
