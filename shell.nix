let
  inputs = import ./.tack;
  pkgs = import ./flake/pkgs.nix {
    inherit inputs;
    system = builtins.currentSystem;
    overlays = [ ];
  };
in
import ./flake/devShell.nix { inherit pkgs; }
