{
  flakeInputs,
  extraConfig,
  lib,
  ...
}:
{
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
      warn-dirty = false;

      substituters = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org/"
      ]
      ++ (lib.optionals extraConfig.hasCuda [
        "https://cache.nixos-cuda.org"
      ]);
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ]
      ++ (lib.optionals extraConfig.hasCuda [
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      ]);
    };
  };
  # Enable unfree
  nixpkgs.config.allowUnfree = true;
}
