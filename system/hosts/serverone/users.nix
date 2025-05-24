{
  pkgs,
  config,
  flakeInputs,
  ...
}:
{
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
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_computerone.pub")
          (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_portatilo.pub")
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
        shell = pkgs.shadow;
        createHome = false;
      };

      edo = {
        name = "edo";
        isNormalUser = true;
        uid = 1002;
        shell = pkgs.shadow;
        createHome = false;
      };

      barbara = {
        name = "barbara";
        isNormalUser = true;
        uid = 1003;
        shell = pkgs.shadow;
        createHome = false;
      };

      containers = {
        name = "containers";
        isSystemUser = true;
        uid = 5000;
        shell = pkgs.shadow;
        group = "containers";
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

      containers = {
        gid = 5000;
        name = "containers";
        members = [ "containers" ];
      };
    };
  };
}
