{
  flakeInputs,
  extraConfig,
  ...
}:
{
  imports = [
    flakeInputs.determinate.nixosModules.default
  ];

  # Periodic cleanup with nh instead of the plain `nix.gc` job: besides
  # collecting unreachable store paths, it also drops old generations,
  # which plain `nix-collect-garbage` leaves in place.
  programs.nh.clean = {
    enable = true;
    dates = "weekly";
    extraArgs = "--keep 5 --keep-since 7d";
  };

  nix = {
    # Make the nixpkgs flake input be used for various nix commands
    registry.nixpkgs = {
      from = {
        id = "nixpkgs";
        type = "indirect";
      };
      flake = flakeInputs.nixpkgs;
    };

    settings = (import ../../flake/caches.nix { cudaSupport = extraConfig.hasCuda; }) // {
      # Enable flakes
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      auto-optimise-store = true;
      warn-dirty = false;
    };
  };
}
