{
  flakeInputs,
  extraConfig,
  lib,
  ...
}:
{
  imports = [
    flakeInputs.determinate.nixosModules.default
  ];

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
    };

    # Make the nixpkgs flake input be used for various nix commands
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
      warn-dirty = false;

      substituters = [
        "https://nix-community.cachix.org"
        "https://catppuccin.cachix.org"
        "https://install.determinate.systems"
        "https://cache.nixos.org/"
      ]
      ++ (lib.optionals extraConfig.hasCuda [
        "https://cache.nixos-cuda.org"
      ]);

      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="

        (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/nix/computerone")
        (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/nix/portatilo")
      ]
      ++ (lib.optionals extraConfig.hasCuda [
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      ]);
    };
  };
}
