{extraConfig, ...}: {
  services.xserver.enable = !extraConfig.wayland;

  services.xserver.windowManager.qtile.enable = true;
  services.xserver.windowManager.qtile.backend =
    if extraConfig.wayland
    then "wayland"
    else "x11";

  # TODO: services.xserver.displayManager.defaultSession =
}
