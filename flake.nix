{
  description = "NixOS config flake";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://catppuccin.cachix.org"
      "https://install.determinate.systems"
      "https://cache.nixos.org/"
      "https://noctalia.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "computerone-1:FwphMHwxn0KLInwuouQcqsNn4J5fkzJNAd4QlJa4Lk8="
      "portatilo-1:KM4PhszcXObDUqfnN0BZNwnya6B+2br39PURy8hy6nA="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

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

    # My flakes
    myPackages = {
      url = "github:billy4479/nix-packages";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

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
    {
      nixpkgs,
      myPackages,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;
      domain = "polpetta.online";

      system = "x86_64-linux";

      pkgsForFlake = import ./flake/pkgs.nix {
        inherit inputs system overlays;
      };

      # The `nvim-fmt` CLI (named to avoid colliding with GNU coreutils'
      # `fmt`, which would otherwise shadow it inside nix devShells).
      fmtPkg = pkgsForFlake.callPackage ./user/modules/applications/editor/nvim/fmt/package.nix { };

      lazyNixPrefetchDocker =
        pkgsForFlake.writeShellScriptBin "nix-prefetch-docker" # sh
          ''
            exec nix run ${nixpkgs}#nix-prefetch-docker -- "$@"
          '';

      lazyPrefetchAllImages =
        pkgsForFlake.writeShellScriptBin "prefetch-all-images" # sh
          ''
            exec ${myPackages}/prefetch-all-images/prefetch-all-images "$@"
          '';

      overlays = [
        (
          final: prev:
          {
            inherit (inputs.ff.packages.${system}) ff;
            # The app flake exposes the binary as `default`; no mc-java
            # equivalent is needed: the image carries the java version
            # the world runs on (see the service file).
            game-server-runner = inputs.game-server-runner.packages.${system}.default;
            inherit (inputs.calendar-proxy.packages.${system}) calendar-proxy;
            inherit (inputs.giuoco-del-divertimento.packages.${system}) giuoco-del-divertimento;
            inherit (inputs.agent-up.packages.${system}) agent-up agent-up-server;
            quote-bot = inputs.quote-bot.packages.${system}.default;
            read-nix-docs = inputs.read-nix-docs.packages.${system}.default;
          }
          // inputs.myPackages.packages.${system}
        )
        inputs.nix-snapshotter.overlays.default
      ];

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

      formatter.${system} = pkgsForFlake.nixfmt;

      checks.${system} = {
        nix-settings = import ./tests/nix-settings.nix {
          pkgs = pkgsForFlake;
          inherit hosts;
        };
        domain = import ./tests/domain.nix {
          pkgs = pkgsForFlake;
          mkHosts =
            domain:
            import ./flake/system.nix {
              inherit
                system
                inputs
                overlays
                domain
                ;
            };
        };
        shell-syntax = import ./tests/shell-syntax.nix {
          pkgs = pkgsForFlake;
          hosts = {
            serverone = hosts.nixosConfigurations.serverone.config;
            vps-proxy = hosts.nixosConfigurations.vps-proxy.config;
          };
        };
        server-policy = import ./tests/server-policy.nix {
          pkgs = pkgsForFlake;
          serverone = hosts.nixosConfigurations.serverone.config;
          vps = hosts.nixosConfigurations.vps-proxy.config;
        };
        monitoring = import ./tests/monitoring.nix {
          inherit domain;
          pkgs = pkgsForFlake;
          ruleFiles = hosts.nixosConfigurations.serverone.config.services.prometheus.ruleFiles;
          scrapeConfigs = hosts.nixosConfigurations.serverone.config.services.prometheus.scrapeConfigs;
          blackboxConfig =
            hosts.nixosConfigurations.serverone.config.services.prometheus.exporters.blackbox.configFile;
        };
        derp-certificates = pkgsForFlake.callPackage ./services/derp-certificates/test.nix { };
        private-store-threshold = pkgsForFlake.callPackage ./containers/private-store-wipe/test.nix { };
        agent-containers = import ./services/pi/test.nix { pkgs = pkgsForFlake; };
        mail-watch = import ./services/mail-watch/test.nix { pkgs = pkgsForFlake; };
        agent-browser = import ./tests/agent-browser.nix {
          pkgs = pkgsForFlake;
          flakeInputs = inputs;
        };
        raw-firewall = import ./tests/raw-firewall.nix {
          pkgs = pkgsForFlake;
          ruleset = hosts.nixosConfigurations.serverone.config.polpetta.generated.rawFirewallFile;
          rawUnit = hosts.nixosConfigurations.serverone.config.systemd.services.polpetta-raw-firewall;
        };
        edge-forwarding = import ./tests/edge-forwarding.nix { pkgs = pkgsForFlake; };
        public-health-monitor = import ./tests/public-health-monitor.nix {
          inherit domain;
          pkgs = pkgsForFlake;
          vps = hosts.nixosConfigurations.vps-proxy.config;
        };
      };

      packages.${system} = rec {
        all-systems =
          let
            mkLink =
              name: target: # sh
              ''
                ln -s ${target} "$out/${name}"
              '';

            systemLinks = lib.mapAttrsToList (
              hostname: config: mkLink "${hostname}-system" config.config.system.build.toplevel
            ) hosts.nixosConfigurations;

            homeLinks = lib.mapAttrsToList (
              homeName: config:
              let
                hostname = lib.last (lib.splitString "@" homeName);
              in
              mkLink "${hostname}-home" config.activationPackage
            ) hosts.homeConfigurations;
          in
          pkgsForFlake.runCommand "all-systems" { } # sh
            ''
              mkdir "$out"
              ${lib.concatStrings (systemLinks ++ homeLinks)}
            '';

        # The full nginx runtime config as deployed on serverone,
        # validated with `nginx -t`; see containers/nginx/package.nix.
        nginx-config =
          let
            serverone = hosts.nixosConfigurations.serverone.config;
          in
          pkgsForFlake.callPackage ./containers/nginx/package.nix {
            inherit domain;
            externalTrafficFrom = serverone.polpetta.externalTrafficFrom;
            nginxVhostsFile = serverone.polpetta.generated.nginxVhostsFile;
          };

        bind9-hosts = pkgsForFlake.callPackage ./services/services/bind9/hosts.nix { };
        bind9-config = pkgsForFlake.callPackage ./services/services/bind9/config.nix {
          inherit domain;
          inherit bind9-hosts;
          # Standalone validation stub: the real per-host fragment is
          # generated by services/module.nix into the container config.
          generated-records = pkgsForFlake.writeText "generated-records.zone" ''
            ; Stub for offline validation; see services/services/bind9.
          '';
        };
        exec-in-container = hosts.nixosConfigurations.serverone.config.system.build.execInContainer;

        nvim-fmt = fmtPkg;
      };

      devShells.${system}.default = pkgsForFlake.mkShell {
        packages = with pkgsForFlake; [
          stylua
          shfmt
          nixfmt
          ruff

          # formatters the nvim conform setup and the nvim-fmt CLI expect for
          # filetypes present in this repo
          jq
          prettier
          rustfmt

          lua-language-server
          nixd

          sops
          age

          dig

          lazyPrefetchAllImages
          lazyNixPrefetchDocker
        ];
      };
    }
    // hosts;
}
