{
  wayland,
  lib,
  ...
}: {
  services.xserver.displayManager.sddm = {
    enable = true;
    wayland.enable = wayland;
  };

  services.xserver.enable = lib.mkForce true; # This sucks but it is what it is, sddm needs it
}
