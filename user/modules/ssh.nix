{ config, ... }:
{
  sops.secrets = {
    ssh_key = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };

  services.ssh-agent = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # Keys are set up in system/modules/desktops/default.nix

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      serverone = {
        hostname = "internal.polpetta.online";
        forwardAgent = true;
        addKeysToAgent = "yes";
      };
      vps-proxy = {
        hostname = "external.polpetta.online";
        forwardAgent = true;
        addKeysToAgent = "yes";
      };
      "*" = {
        # forwardAgent = false;
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
      };
    };
  };
}
