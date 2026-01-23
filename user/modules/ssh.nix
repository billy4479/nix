{ config, ... }:
{
  sops.secrets = {
    ssh_key = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };

  programs.ssh = {
    enable = true;

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
