# My nix flake

This flake contains my NixOS + home-manager configuration.

## Binary caches and packages

Cache URLs and public keys live in `flake.nix` under `nixConfig`. NixOS reuses
these through `flake/caches.nix`, enabling the CUDA cache only on CUDA hosts.
CI builds use `--accept-flake-config` to accept the caches non-interactively.
Locally, accept and remember the settings when Nix prompts to avoid passing the
flag on subsequent builds.

`flake/pkgs.nix` is the shared package-set constructor for flake tools, NixOS,
and Home Manager. All allow unfree packages; CUDA support is enabled only for
hosts with `hasCuda = true`.

## Domain

The `domain` binding in `flake.nix` is the single source of truth for the base
DNS domain. It is exported as `.#domain` and passed to NixOS and Home Manager
modules. Config templates use `@domain@`, substituted when built.

To change domains, edit that binding and rebuild the affected systems and homes.
DNS registration, external DNS records, certificate issuance, secrets and OAuth
client registrations still need to be migrated separately. Existing identity
emails must not be renamed blindly: see `docs/TSIDP.md`. Runbooks under `docs/`
retain concrete examples for the current deployment.
