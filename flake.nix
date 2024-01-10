{
  description = "NixOS config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:Stonks3141/ctp-nix";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    catppuccin-vsc = {
      url = "github:catppuccin/vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    alejandra = {
      url = "github:kamadorueda/alejandra/3.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    catppuccin,
    nix-vscode-extensions,
    catppuccin-vsc,
    alejandra,
    plasma-manager,
    ...
  }: let
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
      alejandra = alejandra.defaultPackage.${system};
      inherit catppuccin-vsc;
    };
  in {
    formatter.${system} = extraArgs.alejandra;
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
          plasma-manager.homeManagerModules.plasma-manager
          ./user
        ];
      };
    };
  };
}
