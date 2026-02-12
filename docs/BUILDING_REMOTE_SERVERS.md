# Building Remote Servers

When working on remote servers, like `serverone` or `vps-proxy` you can connect to them via ssh using their hostname.

You can build their system configuration and copy it to target using the `build-host-and-copy <HOSTNAME>` command.
Activating the new system requires ssh-ing into the server and running `activate-system <SYSTEM_DERIVATION_PATH>` where the derivation path is outputed by the previous command.
Activation requires user intervention to authenticate with sudo.
