{ flakeInputs, ... }:
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
    };
  };
  # Enable unfree
  nixpkgs.config.allowUnfree = true;
}
