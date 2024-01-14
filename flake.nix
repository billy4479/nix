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

    # Shortcuts
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;
    nixos = nixpkgs.lib.nixosSystem;

    user = {
      username = "billy";
      fullName = "Billy Panciotto";
    };

    # specialArgs/extraSpecialArgs for nixos config and home-manager
    extraArgs = {
      extraConfig = {
        desktop = "kde";
        wayland = true;
        bluetooth = true;

        catppuccinColors = {
          flavour = "frappe";
          accent = "green";
        };

        inherit user;
      };

      extraPkgs = {
        vscode-extensions = nix-vscode-extensions.extensions.${system};
        spicetifyPkgs = spicetify-nix.packages.${system}.default;
        inherit catppuccin-vsc;
      };
    };

    # Default home-manager configuration
    hmCfg = args:
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = lib.recursiveUpdate extraArgs args;
        modules = [
          catppuccin.homeManagerModules.catppuccin
          plasma-manager.homeManagerModules.plasma-manager
          spicetify-nix.homeManagerModule
          ./user
        ];
      };
  in {
    formatter.${system} = pkgs.alejandra;
    nixosConfigurations = {
      nixbox = nixos {
        inherit system;
        specialArgs = lib.recursiveUpdate extraArgs {extraConfig.bluetooth = "false";};
        modules = [
          ./system
          ./system/hosts/vm
        ];
      };
      computerone = nixos {
        inherit system;
        specialArgs =
          lib.recursiveUpdate
          extraArgs
          {
            extraConfig.desktop = "qtile";
            extraConfig.wayland = false;
          };
        modules = [
          ./system
          ./system/hosts/computerone
        ];
      };
      portatilo = nixos {
        inherit system;
        specialArgs = extraArgs;
        modules = [
          ./system
          ./system/hosts/portatilo
        ];
      };
    };
    homeConfigurations = {
      "${user.username}@nixbox" = hmCfg {};
      "${user.username}@portatilo" = hmCfg {};
      "${user.username}@computerone" = hmCfg {
        extraConfig.desktop = "qtile";
        extraConfig.wayland = false;
      };
    };
  };
}
