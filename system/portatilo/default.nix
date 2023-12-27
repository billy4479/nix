{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "portatilo";

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };

  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = "billy";
  };
}
