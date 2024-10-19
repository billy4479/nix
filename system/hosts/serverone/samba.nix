{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        "hosts allow" = "192.168.1.0/24";
        "hosts deny" = "0.0.0.0/0";
      };

      "nas-hdd" = {
        "path" = "/mnt/HDD/generic";
        "browsable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0660";
        "directory mask" = "0770";
        "valid users" = "@family";
      };

      "nas-ssd" = {
        "path" = "/mnt/SSD/generic";
        "browsable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0660";
        "directory mask" = "0770";
        "valid users" = "@family";
      };

      "nas-timemachine" = {
        "path" = "/mnt/HDD/timemachine";
        "browsable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0660";
        "directory mask" = "0770";
        "valid users" = "@family";

        "fruit:aapl" = "yes";
        "fruit:time machine" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  sops.secrets = {
    "smbpasswd/billy" = { };
    "smbpasswd/luke" = { };
    "smbpasswd/barbara" = { };
    "smbpasswd/edo" = { };
  };

  # Automatic smbpasswd
  system.activationScripts.smbpasswd.text =
    lib.concatMapStringsSep "\n"
      (
        user:
        let
          passwordFile = config.sops.secrets."smbpasswd/${user}".path;
        in
        ''
          { cat '${passwordFile}'; echo ""; cat '${passwordFile}'; echo ""; } \
                      | "${pkgs.samba}/bin/smbpasswd" -s -a '${user}'  
        ''
      )
      [
        "billy"
        "luke"
        "edo"
        "barbara"
      ];
}
