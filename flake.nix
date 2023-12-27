{
  description = "NixOS config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:Stonks3141/ctp-nix";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, catppuccin, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      nixos = nixpkgs.lib.nixosSystem;
      hmCfg = home-manager.lib.homeManagerConfiguration;
      extraArgs = {
        wayland = true;
        user = {
          username = "billy";
          fullName = "Billy Panciotto";
        };

      };
    in
    {
      formatter.${system} = pkgs.nixpkgs-fmt;
      nixosConfigurations = {
        nixbox = nixos {
          inherit system;
          specialArgs = extraArgs;
          modules = [
            ./system
            ./system/vm
          ];
        };
        portatilo = nixos {
          inherit system;
          specialArgs = extraArgs;
          modules = [
            ./system
            ./system/portatilo
          ];
        };
      };
      homeConfigurations = {
        billy = hmCfg {
          inherit pkgs;
          extraSpecialArgs = extraArgs;
          modules = [
            catppuccin.homeManagerModules.catppuccin
            ./user
          ];
        };
      };
    };
}
