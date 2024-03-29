{
  config,
  pkgs,
  lib,
  extraConfig,
  flakeInputs,
  ...
}: {
  imports =
    [
      ./modules/locale.nix
      ./modules/main-user.nix
      ./modules/sddm.nix
      ./modules/sound.nix
    ]
    ++ lib.optional extraConfig.bluetooth ./modules/bluetooth.nix;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # It should help in desktop use
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
    };

    # Make the nixpkgs flake input be used for various nix commands
    # https://github.com/TLATER/dotfiles/blob/master/nixos-config/default.nix
    nixPath = ["nixpkgs=${flakeInputs.nixpkgs}"];
    registry.nixpkgs = {
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
      flake = flakeInputs.nixpkgs;
    };

    settings = {
      # Enable flakes
      experimental-features = ["nix-command" "flakes"];

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
  };
  services.resolved.enable = lib.mkForce false;

  main-user = {
    enable = true;
    userName = extraConfig.user.username;
    fullName = extraConfig.user.fullName;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    neovim
    file
  ];

  # Many file managers need this
  services.gvfs.enable = true;

  # This is also quite useful since many GUI apps need this
  security.polkit.enable = true;

  # We want this so we can enable udiskie in home-manager
  services.udisks2.enable = true;

  # https://discourse.nixos.org/t/error-gdbus-error-org-freedesktop-dbus-error-serviceunknown-the-name-ca-desrt-dconf-was-not-provided-by-any-service-files/29111/2
  programs.dconf.enable = true;

  programs.adb.enable = true;

  programs.zsh.enable = true;
  # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.enableCompletion
  environment.pathsToLink = ["/share/zsh"];

  services.openssh.enable = true;

  system.stateVersion = "23.11";
}
