# Nix Packages

This directory contains my own Nix packages, integrated into the parent
flake. There is no separate package flake or lock file: dependencies are
pinned in the repository's root `flake.lock`.

Package outputs are available with `nix build .#<package>` from the repository
root, and the shared overlay exposes them to NixOS and Home Manager.

## Packaging

Check Nixpkgs before adding a package and follow its manual for the relevant
build system. Nixpkgs already provides `opencode`, `t3code`, `tsidp`, and
`tailscale.derper`; the local packages retain their own versions and customizations.

Prefer standard build helpers and phases, preserve phase hooks, and annotate
embedded scripts with their language. Use `stdenvNoCC` when no compiler is needed,
keep build tools out of runtime dependencies, and install only runtime files.
Native Node.js addons still need a compiler, even when the application is JavaScript.

Before committing, format changed files with `nvim-fmt`, and run
`nix flake check --no-build`. Build changed packages and their `passthru.tests`
where provided. Compare `nix path-info --closure-size` before and after dependency
changes rather than assuming the closure is smaller.

## Updating packages

Every package with an upstream has an `update.sh` next to it (wired up as
`passthru.updateScript`). From the repository root:

    ./packages/update.sh                  # update everything
    ./packages/update.sh derper tsidp     # update a subset
    ./packages/derper/update.sh           # update a single package

The scripts bump the version and refresh every hash themselves, including
lock files like `deps.json` and the node_modules hashes — and then build the
package as verification. Nothing is committed automatically.

Requirements: nix with flakes, `curl` and `jq`; `nix-update` is fetched from
the nixpkgs registry when not installed. Set `GITHUB_TOKEN` to raise the
GitHub API rate limit.

`searxng-cli` has no update script on purpose, and `prefetch-all-images` has
no upstream to track.
