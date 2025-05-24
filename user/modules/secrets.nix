{
  extraConfig,
  config,
  flakeInputs,
  ...
}:
{
  sops = {
    defaultSopsFile = "${flakeInputs.secrets-repo}/${extraConfig.hostname}.yaml";
    age.keyFile = "/var/lib/sops-nix/key.txt";
    validateSopsFiles = false;

    secrets = {
      ssh_key = {
        path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      };
    };
  };
}
