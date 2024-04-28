{
  extraConfig,
  lib,
  ...
}: {
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = extraConfig.wayland;
  };

  services.xserver.enable = lib.mkForce true; # This sucks but it is what it is, sddm needs it
}
