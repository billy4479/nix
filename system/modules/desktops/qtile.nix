{wayland, ...}: {
  services.xserver.enable = !wayland;

  services.xserver.windowManager.qtile.enable = true;
  services.xserver.windowManager.qtile.backend =
    if wayland
    then "wayland"
    else "x11";

  # TODO: services.xserver.displayManager.defaultSession =
}
