{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.main-user;
in
{
  options.main-user = {
    enable = lib.mkEnableOption "enable user module";

    userName = lib.mkOption {
      default = "user";
      description = ''
        username
      '';
    };
    fullName = lib.mkOption {
      default = "main user";
      description = ''
        user's full name
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.userName} = {
      isNormalUser = true;
      initialPassword = "password";
      description = cfg.fullName;
      shell = pkgs.zsh;
      extraGroups = [
        "wheel"
        "networkmanager"
        "adbusers"
        "libvirtd"
      ];
    };
  };
}
