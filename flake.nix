{
  description = "NixOS config flake";

  outputs =
    { self }:
    let
      inputs = import ./.tack;

      domain = "polpetta.online";

      system = "x86_64-linux";

      pkgs = import ./flake/pkgs.nix {
        inherit inputs system overlays;
      };

      overlays = import ./flake/overlays.nix { inherit inputs system; };

      hosts = import ./flake/system.nix {
        inherit
          system
          inputs
          overlays
          domain
          ;
      };

    in
    {
      inherit domain;

      formatter.${system} = pkgs.nixfmt;

      checks.${system} = import ./flake/checks.nix {
        inherit
          pkgs
          hosts
          inputs
          system
          overlays
          domain
          ;
      };

      packages.${system} =
        (import ./packages { inherit pkgs inputs; })
        // (import ./flake/packages.nix {
          inherit pkgs hosts domain;
        });

      devShells.${system}.default = import ./flake/devShell.nix {
        inherit pkgs;
      };
    }
    // hosts;
}
