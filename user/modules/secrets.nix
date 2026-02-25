{
  extraConfig,
  flakeInputs,
  ...
}:
{
  sops = {
    defaultSopsFile = "${flakeInputs.secrets-repo}/${extraConfig.hostname}.yaml";
    age.keyFile = "/var/lib/sops-nix/key.txt";
    validateSopsFiles = true;
  };
}
