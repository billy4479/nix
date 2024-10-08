{ extraConfig, ... }:
{
  # https://nixos.wiki/wiki/Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
  services.blueman.enable = extraConfig.desktop != "kde"; # It seems like KDE does its own thing
}
