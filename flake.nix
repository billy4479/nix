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
      home-manager,
      catppuccin,
      nix-vscode-extensions,
      catppuccin-vsc,
      plasma-manager,
      spicetify-nix,
      server-tool,
      sops-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Shortcuts
      pkgs = import nixpkgs {
        config.allowUnfree = true;
        inherit system;
      };

      lib = nixpkgs.lib;

      my-packages = import ./packages { inherit pkgs; } // {
        server-tool = server-tool.packages.${system}.default;
      };

      user = {
        username = "billy";
        fullName = "Billy Panciotto";
      };

      # https://github.com/catppuccin/nix/blob/5501cb508c2d4224d932a0b924d75454b68680bf/modules/lib/default.nix#L79
      mkUpper =
        str:
        (lib.toUpper (builtins.substring 0 1 str)) + (builtins.substring 1 (builtins.stringLength str) str);

      mkCatppuccinColors =
        { flavor, accent }:
        rec {
          inherit flavor accent;
          flavorWithAccent = if flavor == "frappe" then "Frappé" else flavor;

          upper = {
            flavor = mkUpper flavor;
            accent = mkUpper accent;
            flavorWithAccent = mkUpper flavorWithAccent;
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
          isServer = false;
          standaloneHomeManager = true;

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

      # This function creates the flake output for a single host:
      # we take a `hostname`, `extraSystemModules` (that we pass to NixOS),
      # and `args` (that we pass to both to NixOS and home-manager).
      hostFn =
        {
          hostname,
          extraSystemModules ? [ ],
          args ? { },
        }:
        let
          specialArgs = lib.recursiveUpdate extraArgs { extraConfig = (args // { inherit hostname; }); };
          defaultHomeManagerModules = [
            catppuccin.homeManagerModules.catppuccin
            plasma-manager.homeManagerModules.plasma-manager
            spicetify-nix.homeManagerModules.default
            sops-nix.homeManagerModules.sops
            ./user
          ];
        in
        {
          nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
            inherit system specialArgs;
            modules =
              [
                ./system
                sops-nix.nixosModules.sops
              ]
              ++ lib.optionals (!specialArgs.extraConfig.standaloneHomeManager) [
                home-manager.nixosModules.home-manager
                {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    extraSpecialArgs = specialArgs;
                    users.${user.username}.imports = defaultHomeManagerModules;
                  };
                }
              ]
              ++ extraSystemModules;
          };

          homeConfigurations =
            if specialArgs.extraConfig.standaloneHomeManager then
              {
                "${user.username}@${hostname}" = home-manager.lib.homeManagerConfiguration {
                  inherit pkgs;
                  extraSpecialArgs = specialArgs;
                  modules = defaultHomeManagerModules;
                };
              }
            else
              { };
        };

      # This function is like `lib.recursiveUpdate` but takes a list instead.
      recursiveMerge = attrList: builtins.foldl' (a: b: lib.recursiveUpdate a b) { } attrList;

      # Now we map `hostProps` to "real" configurations using `hostFn` and we merge them.
      createAndMergeHosts = hostProps: recursiveMerge (map hostFn hostProps);
    in
    {
      formatter.${system} = pkgs.nixfmt-rfc-style;
    }
    # Finally we define our `hostProps`:
    # these are the real configuration changes I want from one host to another.
    // createAndMergeHosts [
      {
        hostname = "nixbox";
        args = {
          bluetooth = false;
        };
        extraSystemModules = [
          ./system/hosts/vm
        ];
      }
      {
        hostname = "portatilo";
        args = { };
        extraSystemModules = [
          ./system/hosts/portatilo
        ];
      }
      {
        hostname = "computerone";
        args = {
          desktop = "qtile";
          wayland = false;
          games = true;
        };
        extraSystemModules = [
          ./system/hosts/computerone
        ];
      }
      {
        hostname = "serverone";
        args = {
          isServer = true;
          standaloneHomeManager = false;
          bluetooth = false;
        };
        extraSystemModules = [
          ./system/hosts/serverone
        ];
      }
    ];
}
