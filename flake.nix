{
  description = "NixOS config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:Stonks3141/ctp-nix";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    spicetify-nix = {
      url = "github:the-argus/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin-vsc = {
      url = "github:catppuccin/vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
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
    plasma-manager,
    spicetify-nix,
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
      spicetifyPkgs = spicetify-nix.packages.${system}.default;
      inherit catppuccin-vsc;
    };
  in {
    formatter.${system} = pkgs.alejandra;
    nixosConfigurations = {
      nixbox = nixos {
        inherit system;
        specialArgs = extraArgs;
        modules = [
          ./system
          ./system/vm
        ];
      };
      computerone = nixos {
        inherit system;
        specialArgs = extraArgs;
        modules = [
          ./system
          ./system/computerone
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
          spicetify-nix.homeManagerModule
          ./user
        ];
      };
    };
  };
}
