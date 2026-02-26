{
  description = "NixOS config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
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

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-snapshotter = {
      url = "github:billy4479/nix-snapshotter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-ui-fix = {
      url = "github:black7375/Firefox-UI-Fix";
      flake = false;
    };

    secrets-repo = {
      url = "git+ssh://git@github.com/billy4479/nix-secrets.git?ref=master&shallow=1";
      flake = false;
    };

    myPackages = {
      url = "github:billy4479/nix-packages";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      myPackages,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      pkgsForFlake = import nixpkgs {
        # config.allowUnfree = true;
        inherit system;
      };

      hosts = import ./flake/system.nix {
        inherit
          system
          inputs
          ;
      };

    in
    {
      formatter.${system} = pkgsForFlake.nixfmt;

      packages.${system} = rec {
        nginx-config = pkgsForFlake.callPackage ./containers/nginx/config.nix { };

        bind9-hosts = pkgsForFlake.callPackage ./containers/bind9/hosts.nix { };
        bind9-config = pkgsForFlake.callPackage ./containers/bind9/config.nix { inherit bind9-hosts; };
      };

      devShells.${system}.default = pkgsForFlake.mkShell {
        packages = with pkgsForFlake; [
          stylua
          shfmt
          nixfmt
          ruff

          lua-language-server
          nixd

          sops
          age

          dig

          myPackages.packages.${system}.prefetch-all-images
          nix-prefetch-docker
        ];
      };
    }
    // hosts;
}
