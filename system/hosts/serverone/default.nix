{
  flakeInputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    flakeInputs.disko.nixosModules.disko
    ./disko.nix

    ./samba.nix
    ./tailscale.nix
    ./containers.nix

    ../../modules/power-management
    ../../modules/graphics/intel.nix
  ];

  # https://github.com/nix-community/disko/issues/581#issuecomment-2260602290
  boot.zfs.extraPools = [
    "hdd_pool"
    "ssd_pool"
  ];

  services = {
    openssh = {
      enable = true;
    };
  };

  sops.secrets.user_password.neededForUsers = true;

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
          (builtins.readFile ../../../secrets/public_keys/billy_computerone.pub)
          (builtins.readFile ../../../secrets/public_keys/billy_portatilo.pub)
        ];

        extraGroups = [
          "wheel"
          "networkmanager"
        ];
      };

      luke = {
        name = "luke";
        isNormalUser = true;
        uid = 1001;
        shell = null;
        createHome = false;
      };

      edo = {
        name = "edo";
        isNormalUser = true;
        uid = 1002;
        shell = null;
        createHome = false;
      };

      barbara = {
        name = "barbara";
        isNormalUser = true;
        uid = 1003;
        shell = null;
        createHome = false;
      };
    };

    groups = {
      admin = {
        gid = 2000;
        name = "admin";
        members = [
          "billy"
        ];
      };

      family = {
        gid = 2001;
        name = "family";
        members = [
          "luke"
          "barbara"
          "edo"
          "billy"
        ];
      };
    };
  };

  networking = {
    hostId = "d3cb129c";
    hostName = "serverone";
    interfaces.enp2s0.wakeOnLan.enable = true;
  };
}
