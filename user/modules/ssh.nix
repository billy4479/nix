{ config, ... }:
{
  sops.secrets = {
    ssh_key = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
    };
  };

  services.ssh-agent = {
    enable = true;
  };

  # Keys are set up in system/modules/desktops/default.nix

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      serverone = {
        HostName = "internal.polpetta.online";
        ForwardAgent = true;
        AddKeysToAgent = "yes";
      };

      vps-proxy = {
        HostName = "external.polpetta.online";
        ForwardAgent = true;
        AddKeysToAgent = "yes";
      };
    };
  };
}
