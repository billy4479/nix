{ pkgs, hosts }:
let
  lib = pkgs.lib;
  flakeConfig = (import ../flake.nix).nixConfig or { };
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
# Cache trust belongs to the daemon, not client-supplied flake settings.
assert lib.assertMsg (
  !(flakeConfig ? trusted-public-keys) && !(flakeConfig ? extra-trusted-public-keys)
) "Flake-supplied cache keys trigger restricted-setting warnings for untrusted users";
assert pkgs.config.allowUnfree && !pkgs.config.cudaSupport;
assert lib.all (value: value) (lib.mapAttrsToList checkHost hosts.nixosConfigurations);
pkgs.writeText "nix-settings" "Shared cache and package policies match.\n"
