{
  pkgs,
  lib,
  extraConfig,
  flakeInputs,
  ...
}:
{
  imports = [
    ./modules/locale.nix
    ./modules/main-user.nix
    ./modules/steam.nix
    ./modules/sddm.nix
    ./modules/sound.nix
  ] ++ lib.optional extraConfig.bluetooth ./modules/bluetooth.nix;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # It should help in desktop use
  # Mhh, it seems like it causes some crashes?
  # boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;
  boot.kernelPackages = pkgs.linuxPackages_zen;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
    };

    # Make the nixpkgs flake input be used for various nix commands
    # https://github.com/TLATER/dotfiles/blob/master/nixos-config/default.nix
    nixPath = [ "nixpkgs=${flakeInputs.nixpkgs}" ];
    registry.nixpkgs = {
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
      flake = flakeInputs.nixpkgs;
    };

    settings = {
      # Enable flakes
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      auto-optimise-store = true;
    };
  };
  # Enable unfree
  nixpkgs.config.allowUnfree = true;

  networking = {
    networkmanager = {
      enable = true;
      dns = "none";
    };
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
    # hosts = {
    #   "0.0.0.0" = [ "www.youtube.com" ];
    # };
  };
  services.resolved.enable = lib.mkForce false;

  main-user = {
    enable = true;
    userName = extraConfig.user.username;
    fullName = extraConfig.user.fullName;
  };

  # These are packages that I need on all users
  environment.systemPackages = with pkgs; [
    neovim
    file
    lsof
    usbutils # lsusb
  ];

  services = {
    gvfs.enable = true;
    udisks2.enable = true;
    printing.enable = true;
    smartd.enable = true;
    openssh.enable = true;
  };

  security.polkit.enable = true;

  programs = {
    # https://discourse.nixos.org/t/error-gdbus-error-org-freedesktop-dbus-error-serviceunknown-the-name-ca-desrt-dconf-was-not-provided-by-any-service-files/29111/2
    dconf.enable = true;
    adb.enable = true;
  };

  programs.zsh.enable = true;
  # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enableCompletion
  environment.pathsToLink = [ "/share/zsh" ];

  system.stateVersion = "23.11";
}
