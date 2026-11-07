# My nix flake

This flake contains my NixOS + home-manager configuration.

## Domain

The `domain` binding in `flake.nix` is the single source of truth for the base
DNS domain. It is exported as `.#domain` and passed to NixOS and Home Manager
modules. Config templates use `@domain@`, substituted when built.

To change domains, edit that binding and rebuild the affected systems and homes.
DNS registration, external DNS records, certificate issuance, secrets and OAuth
client registrations still need to be migrated separately. Existing identity
emails must not be renamed blindly: see `docs/TSIDP.md`. Runbooks under `docs/`
retain concrete examples for the current deployment.
