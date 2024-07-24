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
  };

  outputs =
    { nixpkgs
    , home-manager
    , catppuccin
    , nix-vscode-extensions
    , catppuccin-vsc
    , plasma-manager
    , spicetify-nix
    , server-tool
    , ...
    } @ inputs:
    let
      system = "x86_64-linux";

      # Shortcuts
      pkgs = import nixpkgs {
        config.allowUnfree = true;
        inherit system;
      };

      lib = nixpkgs.lib;
      nixos = nixpkgs.lib.nixosSystem;

      my-packages =
        import ./packages { inherit pkgs; }
        // {
          server-tool = server-tool.packages.${system}.default;
        };

      user = {
        username = "billy";
        fullName = "Billy Panciotto";
      };

      # https://github.com/Stonks3141/ctp-nix/blob/main/modules/lib/default.nix#L49C1-L51C78
      mkUpper = str:
        (lib.toUpper (builtins.substring 0 1 str)) + (builtins.substring 1 (builtins.stringLength str) str);

      mkCatppuccinColors =
        { flavor
        , accent
        }: {
          inherit flavor accent;
          upper = {
            flavor = mkUpper flavor;
            accent = mkUpper accent;
          };
        };

      # WARNING: the following part might look like a mess but it's actually quite straight forward.
      #          We have all this code because we want to share the same `specialArgs`/`extraSpecialArgs` between
      #          the nixos config and the home-manager config.

      # First we define the specialArgs/extraSpecialArgs for nixos config and home-manager
      extraArgs = {
        extraConfig = {
          desktop = "kde";
          wayland = true;
          bluetooth = true;
          games = false;

          catppuccinColors = mkCatppuccinColors {
            flavor = "frappe";
            accent = "green";
          };

          inherit user;
        };

        extraPkgs = {
          vscode-extensions = nix-vscode-extensions.extensions.${system};
          spicetifyPkgs = spicetify-nix.legacyPackages.${system};
          inherit catppuccin-vsc my-packages;
        };

        flakeInputs = inputs;
      };

      # This function takes some `args`, merges them with our default `extraArgs`
      # and creates a "default" home-manager config with `args` added on top.
      hmCfg = args:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = lib.recursiveUpdate extraArgs { extraConfig = args; };
          modules = [
            catppuccin.homeManagerModules.catppuccin
            plasma-manager.homeManagerModules.plasma-manager
            spicetify-nix.homeManagerModules.default
            ./user
          ];
        };

      # This function does pretty much the same of the above one but with the nixos config:
      # here we take `args` and `extraSystemModules`. `args` is added to `specialArgs`,
      # while `extraSystemModules` is a list of modules that gets added to the default ones.
      nixCfg =
        { extraSystemModules
        , args
        }:
        nixos {
          inherit system;
          specialArgs = lib.recursiveUpdate extraArgs { extraConfig = args; };
          modules = [ ./system ] ++ extraSystemModules;
        };

      # This function creates the flake output for a single host:
      # we take a `hostname`, `extraSystemModules` (that we pass to `nixCfg`),
      # and `args` (that we pass to `nixCfg` and `hmCfg`).
      hostFn =
        { hostname
        , extraSystemModules ? [ ]
        , args ? { }
        }: {
          nixosConfigurations.${hostname} = nixCfg {
            inherit extraSystemModules;
            args = args // { inherit hostname; };
          };
          homeConfigurations."${user.username}@${hostname}" = hmCfg (args // { inherit hostname; });
        };

      # This function is like `lib.recursiveUpdate` but takes a list instead.
      recursiveMerge = attrList: builtins.foldl' (a: b: lib.recursiveUpdate a b) { } attrList;

      # Now we map `hostProps` to "real" configurations using `hostFn` and we merge them.
      createAndMergeHosts = hostProps: recursiveMerge (map hostFn hostProps);
    in
    {
      formatter.${system} = pkgs.nixpkgs-fmt;
    }
    # Finally we define our `hostProps`:
    # these are the real configuration changes I want from one host to another.
    // createAndMergeHosts [
      {
        hostname = "nixbox";
        args = { bluetooth = "false"; };
        extraSystemModules = [ ./system/hosts/vm ];
      }
      {
        hostname = "portatilo";
        args = { };
        extraSystemModules = [ ./system/hosts/portatilo ];
      }
      {
        hostname = "computerone";
        args = {
          desktop = "qtile";
          wayland = false;
          games = true;
        };
        extraSystemModules = [ ./system/hosts/computerone ];
      }
    ];
}
