# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  user,
  desktop,
  lib,
  bluetooth,
  ...
}: {
  imports =
    [
      ./modules/locale.nix
      ./modules/main-user.nix
      ./modules/sddm.nix
      ./modules/sound.nix
    ]
    ++ lib.optional bluetooth ./modules/bluetooth.nix;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Enable unfree
  nixpkgs.config.allowUnfree = true;

  # Enable networking
  networking.networkmanager.enable = true;

  main-user = {
    enable = true;
    userName = user.username;
    fullName = user.fullName;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    neovim
    file
  ];

  programs.zsh.enable = true;
  # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enableCompletion
  environment.pathsToLink = ["/share/zsh"];

  services.openssh.enable = true;

  system.stateVersion = "23.11";
}
