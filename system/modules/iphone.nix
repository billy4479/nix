{ pkgs, ... }:
{
  # https://wiki.nixos.org/wiki/Libimobiledevice

  services.usbmuxd.enable = true;
  environment.systemPackages = with pkgs; [
    libimobiledevice
    ifuse
  ];
}
