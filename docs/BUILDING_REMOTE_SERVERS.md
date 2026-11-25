# Building Remote Servers

## Deploy serverone from the local workspace

From the workspace container, commit the changes you want to deploy, then run:

```sh
cd /workspace/nix
./scripts/stage-serverone.sh
```

The script sends the current local commit over SSH and builds it on `serverone`.
There's no need to push to GitHub. Uncommitted changes are not included.
The host uses the committed `flake.lock` and its existing access to private inputs.

On success, run the printed `ssh -t serverone activate-system /nix/store/...`
command from an interactive terminal and authenticate with sudo. The most recent
successful build is kept alive by `~/.local/state/serverone-deploy/result` on
`serverone`; staging does not switch the running system. Use `--dry-run` to see
what Nix would build without staging a new result.

## Build elsewhere and copy to a remote server

When working on remote servers like `serverone` or `vps-proxy`, you can connect to them via SSH using their hostname.

You can build their system configuration and copy it to target using the `build-host-and-copy <HOSTNAME>` command.
Activating the new system requires ssh-ing into the server and running `activate-system <SYSTEM_DERIVATION_PATH>` where the derivation path is outputed by the previous command.
Activation requires user intervention to authenticate with sudo.
