{
  description = "NixOS config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    catppuccin.url = "github:catppuccin/nix";
    flake-utils.url = "github:numtide/flake-utils";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
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

    server-tool = {
      url = "github:billy4479/server-tool";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      server-tool,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      pkgsForFlake = import nixpkgs {
        # config.allowUnfree = true;
        inherit system;
      };

      # TODO: this should definitely be an overlay.
      myPackagesFn =
        pkgs:
        (
          import ./packages { inherit pkgs; }
          // {
            server-tool = server-tool.packages.${system}.default;
          }
        );

      hosts = import ./flake/system.nix {
        inherit
          system
          myPackagesFn
          inputs
          ;
      };

    in
    {
      formatter.${system} = pkgsForFlake.nixfmt-rfc-style;

      devShells.${system}.default = pkgsForFlake.mkShell {
        packages = with pkgsForFlake; [
          stylua
          shfmt
          nixfmt-rfc-style

          lua-language-server
          nixd

          sops
          age

          wireguard-tools
        ];
      };
    }
    // hosts;
}
