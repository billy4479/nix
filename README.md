# My nix flake

This flake contains my NixOS + home-manager configuration.

## Binary caches and packages

Cache URLs and public keys live in `flake/caches.nix`. NixOS installs these
system-wide, enabling the CUDA cache only on CUDA hosts. CI configures the same
caches explicitly through `.github/actions/setup-nix` (including the CUDA cache).
The flake does not override cache settings on the client: doing so causes
restricted-setting warnings for untrusted users, even when the daemon already
trusts those keys. No local flake-cache approval or additional user privileges
are needed on managed hosts.

`flake/pkgs.nix` is the shared package-set constructor for flake tools, NixOS,
and Home Manager. All allow unfree packages; CUDA support is enabled only for
hosts with `hasCuda = true`.

Local package definitions live in [`packages/`](packages/README.md), sharing
this flake's inputs and `flake.lock`. They are available through `pkgs` in
system/home configurations and as `nix build .#<package>` outputs. Update them
with `./packages/update.sh` or `./packages/update.sh <package> ...`.

## Domain

The `domain` binding in `flake.nix` is the single source of truth for the base
DNS domain. It is exported as `.#domain` and passed to NixOS and Home Manager
modules. Config templates use `@domain@`, substituted when built.

To change domains, edit that binding and rebuild the affected systems and homes.
DNS registration, external DNS records, certificate issuance, secrets and OAuth
client registrations still need to be migrated separately. Existing identity
emails must not be renamed blindly: see `docs/TSIDP.md`. Runbooks under `docs/`
retain concrete examples for the current deployment.
