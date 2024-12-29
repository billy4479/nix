{
  pkgs,
  system,
  my-packages,
  inputs,
}:
let
  lib = inputs.nixpkgs.lib;

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

  # This function creates the flake output for a single host:
  # we take a `hostname`, `extraSystemModules` (that we pass to NixOS),
  # and `args` (that we pass to both to NixOS and home-manager).
  hostFn =
    defaultOptions:
    {
      hostname,
      extraSystemModules ? [ ],
      args,
    }:
    let
      defaultedArgs = lib.recursiveUpdate defaultOptions args;
      user = defaultedArgs.user;

      specialArgs = {
        extraConfig = builtins.removeAttrs (lib.recursiveUpdate defaultedArgs {
          catppuccinColors = mkCatppuccinColors defaultedArgs.catppuccin;
          inherit hostname;
        }) [ "catppuccin" ];

        extraPkgs = {
          vscode-extensions = inputs.nix-vscode-extensions.extensions.${system};
          spicetifyPkgs = inputs.spicetify-nix.legacyPackages.${system};
          inherit (inputs) catppuccin-vsc;
          inherit my-packages;
        };
        flakeInputs = inputs;
      };

      defaultHomeManagerModules = [
        inputs.catppuccin.homeManagerModules.catppuccin
        inputs.plasma-manager.homeManagerModules.plasma-manager
        inputs.spicetify-nix.homeManagerModules.default
        inputs.sops-nix.homeManagerModules.sops
        ../user
      ];
    in
    {
      nixosConfigurations.${hostname} = inputs.nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules =
          [
            ../system
            inputs.sops-nix.nixosModules.sops
          ]
          ++ lib.optionals (!specialArgs.extraConfig.standaloneHomeManager) [
            inputs.home-manager.nixosModules.home-manager
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
            "${user.username}@${hostname}" = inputs.home-manager.lib.homeManagerConfiguration {
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
  createAndMergeHosts =
    defaultOptions: hostProps: recursiveMerge (map (prop: hostFn defaultOptions prop) hostProps);
in
createAndMergeHosts
