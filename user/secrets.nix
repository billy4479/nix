{ extraConfig, config, ... }:
{
  sops = {
    defaultSopsFile = ../secrets/${extraConfig.hostname}.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    validateSopsFiles = false;

    secrets = {
      ssh_key = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
    };
  };
}
