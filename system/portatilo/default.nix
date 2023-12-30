{
  pkgs,
  user,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../bluetooth.nix
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
    user = user.username;
  };
}
