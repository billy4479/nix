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
      url = "github:billy4479/nix-snapshotter/aa15121743bc5218be8eb3e8b457d0f67a4203e6";
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

    niri = {
      # See https://github.com/sodiboo/niri-flake/pull/1731
      # url = "github:sodiboo/niri-flake";
      url = "github:myume/niri-flake/blur";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
      # This is commented out to allow caching
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };

    # My flakes

    agent-up = {
      url = "github:billy4479/agent-up";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    quote-bot = {
      url = "git+ssh://git@github.com/billy4479/quote-bot.git?ref=master&shallow=1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    calendar-proxy = {
      url = "git+ssh://git@github.com/billy4479/calendar-proxy-v2.git?ref=master&shallow=1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    giuoco-del-divertimento = {
      url = "git+ssh://git@github.com/billy4479/giuoco-del-divertimento.git?ref=master&shallow=1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    game-server-runner = {
      url = "github:billy4479/game-server-runner";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    ff = {
      url = "git+ssh://git@github.com/billy4479/ff.git?ref=master&shallow=1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    read-nix-docs = {
      url = "github:billy4479/read-nix-docs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
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
        inherit pkgs inputs;
      };
    }
    // hosts;
}
