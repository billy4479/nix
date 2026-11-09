{ pkgs, hosts }:
let
  lib = pkgs.lib;
  checkHost =
    name: host:
    let
      cudaSupport = name == "computerone";
      caches = import ../flake/caches.nix { inherit cudaSupport; };
      settings = host.config.nix.settings;
    in
    lib.assertMsg (
      host.pkgs.config.allowUnfree
      && host.pkgs.config.cudaSupport == cudaSupport
      && lib.all (url: lib.elem url settings.substituters) caches.substituters
      && lib.all (key: lib.elem key settings.trusted-public-keys) caches.trusted-public-keys
      && lib.elem "https://cache.nixos-cuda.org" settings.substituters == cudaSupport
      &&
        lib.any (key: lib.hasPrefix "cache.nixos-cuda.org:" key) settings.trusted-public-keys == cudaSupport
    ) "${name}: package policy or shared caches differ from the expected configuration";
in
assert pkgs.config.allowUnfree && !pkgs.config.cudaSupport;
assert lib.all (value: value) (lib.mapAttrsToList checkHost hosts.nixosConfigurations);
pkgs.writeText "nix-settings" "Shared cache and package policies match.\n"
