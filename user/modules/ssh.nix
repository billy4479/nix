{
  extraConfig,
  flakeInputs,
  config,
  ...
}:
{
  sops.secrets = {
    ssh_key = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };

  users.users.${extraConfig.user.username}.openssh.authorizedKeys = [
    (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_computerone.pub")
    (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_portatilo.pub")
    (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_nord.pub")
  ];

  programs.ssh = {
    enable = true;
    startAgent = true;

    matchBlocks = {
      serverone = {
        hostname = "10.0.0.1";
        forwardAgent = true;
        addKeysToAgent = "yes";
      };
      vps-proxy = {
        hostname = "87.106.25.93";
        forwardAgent = true;
        addKeysToAgent = "yes";
      };
    };
  };
}
