{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix

    ../../modules/desktops
  ];

  networking.hostName = "nixbox";

  services.spice-vdagentd.enable = true;
  services.xserver.videoDrivers = [ "qxl" ];
}
