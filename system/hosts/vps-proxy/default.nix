{
  flakeInputs,
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
  ];

  sops.secrets.user_password.neededForUsers = true;

  services = {
    openssh = {
      enable = true;
    };
  };

  zramSwap.enable = true;

  users = {
    mutableUsers = false;
    users = {
      billy = {
        name = "billy";
        description = "Billy Panciotto";
        isNormalUser = true;
        uid = 1000;

        shell = pkgs.zsh;

        hashedPasswordFile = config.sops.secrets.user_password.path;
        openssh.authorizedKeys.keys = [
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_computerone.pub")
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_portatilo.pub")
        ];

        extraGroups = [
          "wheel"
          "networkmanager"
        ];
      };
    };
  };

  networking = {
    hostName = "vps-proxy";
  };

  documentation.nixos.enable = false;
}
