{ ... }:
{

  imports = [
    ./db.nix
    ./valkey.nix
    ./server.nix
    ./ml.nix
  ];

  sops.secrets.immichEnv = { };
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };
}
