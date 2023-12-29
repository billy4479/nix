{
  description = "NixOS config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:Stonks3141/ctp-nix";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, catppuccin, nix-vscode-extensions, ... }:
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
        vscode-extensions = nix-vscode-extensions.extensions.${system};
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
