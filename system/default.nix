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
    ./modules/ssh.nix
  ]
  ++ lib.optional extraConfig.bluetooth ./modules/bluetooth.nix;

  # These are packages that I need on all users
  environment.systemPackages = with pkgs; [
    neovim
    file

    lsof
    usbutils # lsusb
    net-tools
    sysstat # iostat
    iotop
  ];

  programs.zsh.enable = true;
  # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enableCompletion
  environment.pathsToLink = [ "/share/zsh" ];

  boot.kernel.sysctl = {
    "kernel.task_delayacct" = 1; # for iotop
  };

  system.stateVersion = "23.11";
}
