{desktop, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix

    (import ../../modules/desktops desktop)
  ];

  networking.hostName = "nixbox";

  services.spice-vdagentd.enable = true;
  services.xserver.videoDrivers = ["qxl"];
}
