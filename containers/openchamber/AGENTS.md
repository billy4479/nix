# OpenChamber Container

You are running inside a container on a host called `serverone`.

- Existing synchronized repositories are available under `/workspace/code` and `/workspace/nix`.
- The home directory, caches, OpenChamber state, and SSH known hosts persist, but they are not synchronized to other machines.
- `/nix` is a private single-user store. Normal `nix build` and `nix shell` commands work without the host Nix daemon. Do not change ownership under `/nix` or assume host store paths are available.
- Use a nix shell when you need to run a program which is not installed.
- The container has no root access and cannot manage the host's systemd units, container runtime, deployment, or secrets.
- Use `ssh computerone`, `ssh portatilo`, `ssh serverone`, or `ssh vps-proxy` when work must run on a specific host. These connections are unprivileged. You MUST get explicit user approval to ssh into other machines, approval is valild for the whole session but just for one machine, if you need to ssh into multiple hosts you must ask for approval multiple times.
- Always leave deployment and secret management to the user.
- To inspect third-party code you can clone repositories them under `/tmp/opencode`. This is preferred over fetching github urls.
