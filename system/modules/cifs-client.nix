{
  pkgs,
  config,
  lib,
  ...
}:
let
  # https://nixos.wiki/wiki/Samba#Samba_Client
  mount_options = lib.concatStringsSep "," [
    "noauto"
    "x-systemd.automount"
    "x-systemd.idle-timeout=5m"
    "x-systemd.device-timeout=5s"
    "x-systemd.mount-timeout=5s"
    "uid=1000"
    "gid=1000"
    "credentials=${config.sops.secrets.cifs_credentials.path}"
  ];
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];

  sops.secrets.cifs_credentials = { };

  fileSystems = {
    "/mnt/serverone/hdd-generic" = {
      device = "//192.168.1.51/nas-hdd";
      fsType = "cifs";
      options = [ mount_options ];
    };

    "/mnt/serverone/ssd-generic" = {
      device = "//192.168.1.51/nas-ssd";
      fsType = "cifs";
      options = [ mount_options ];
    };
  };
}
