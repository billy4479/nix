# Building Remote Servers

## Deploy serverone from the local workspace

Commit the changes you want to deploy in `/workspace/nix`, then run this
**on serverone** as your normal user:

```sh
/mnt/SSD/apps/openchamber/workspaces/nix/scripts/stage-serverone.sh --switch
```

The script builds the committed `HEAD` from the host's view of the shared
workspace. There's no GitHub push or source upload. Nix uses the committed
`flake.lock` and the host's existing access to private inputs. After a successful
build, activation requires sudo authentication.

Omit `--switch` to build without activating. The script prints the activation
command and keeps the latest successful build alive at
`~/.local/state/serverone-deploy/result`. Use `--dry-run` to see what Nix would
build without staging a new result.

## Build elsewhere and copy to a remote server

When working on remote servers like `serverone` or `vps-proxy`, you can connect to them via SSH using their hostname.

You can build their system configuration and copy it to target using the `build-host-and-copy <HOSTNAME>` command.
Activating the new system requires ssh-ing into the server and running `activate-system <SYSTEM_DERIVATION_PATH>` where the derivation path is outputed by the previous command.
Activation requires user intervention to authenticate with sudo.
