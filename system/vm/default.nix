{...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixbox";

  services.spice-vdagentd.enable = true;
  services.xserver.videoDrivers = ["qxl"];

  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = "billy";
  };
}
