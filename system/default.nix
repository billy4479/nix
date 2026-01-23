{
  pkgs,
  lib,
  extraConfig,
  ...
}:
{
  imports = [
    ./modules/locale.nix
    ./modules/bootloader.nix
    ./modules/network.nix
    ./modules/nix.nix
    ./modules/secrets.nix
    ./modules/sensors.nix
  ]
  ++ lib.optional extraConfig.bluetooth ./modules/bluetooth.nix;

  # These are packages that I need on all users
  environment.systemPackages = with pkgs; [
    neovim
    file
    lsof
    usbutils # lsusb
    net-tools
  ];

  services.smartd.enable = true;

  programs.zsh.enable = true;
  # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enableCompletion
  environment.pathsToLink = [ "/share/zsh" ];

  system.stateVersion = "23.11";
}
