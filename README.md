# My nix flake

This flake contains my NixOS + home-manager configuration.

## Dependencies and development shell

[Tack](https://docs.manic.systems/tack) manages the root inputs. Edit
`.tack/pins.toml` to change sources or `follows` rules. Use `tack look` to
preview updates and `tack update <input>` to update a single pin. Commit both
`.tack/pins.toml` and `.tack/pins.lock.json` when they change.

If Tack is not installed, run it with the version matching the vendored resolver:

```sh
nix run github:manic-systems/tack/673997981720feebb3870645932b6cfe6657db9f -- look nixpkgs
```

Run `direnv allow` for the development shell, or `nix-shell` without direnv.
Both load `shell.nix` directly and only need the pinned nixpkgs. Flake commands
such as `nix develop` and `nix build .#<package>` still work.
