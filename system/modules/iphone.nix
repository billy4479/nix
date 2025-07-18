{ pkgs, ... }:
{
  # https://wiki.nixos.org/wiki/Libimobiledevice

  services.usbmuxd = {
    enable = true;
    package = pkgs.usbmuxd2;
  };

  environment.systemPackages = with pkgs; [
    libimobiledevice
    ifuse
  ];
}
