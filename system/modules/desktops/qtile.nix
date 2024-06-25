{ pkgs, extraConfig, ... }: {
  services.xserver.enable = !extraConfig.wayland;

  services.xserver.windowManager.qtile.enable = true;

  xdg.portal = {
    enable = extraConfig.wayland;
    config.common.default = [ "xlr" ];
    wlr.enable = extraConfig.wayland;
    extraPortals = with pkgs; [ xdg-desktop-portal-kde ];
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # idk if we actually need it
  services.libinput.enable = true;

  services.displayManager.defaultSession = "qtile";
}
