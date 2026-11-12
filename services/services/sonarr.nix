{ pkgs, lib, ... }:
let
  name = "sonarr";
  baseHDDDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/${name}";
  setfacl = lib.getExe' pkgs.acl "setfacl";
  sharedPermissionScript = # sh
    ''
      currentPerm=$(stat -c %u:%g "${baseHDDDir}")
      desiredPerm="0:5000"
      echo "Current permissions of ${baseHDDDir}: $currentPerm"
      if [ "$currentPerm" != "$desiredPerm" ]; then
        echo "Changing permissions for ${baseHDDDir}"
        chown -R "$desiredPerm" "${baseHDDDir}"
        chmod -R g+rwX "${baseHDDDir}"
        chmod g+s "${baseHDDDir}"
        ${setfacl} -R -m d:g:containers:rwX,g:containers:rwX "${baseHDDDir}"
      else
        echo "Permissions for ${baseHDDDir} are good"
      fi
    '';
in
{
  polpetta.services.sonarr = {
    container = {
      id = 9;

      entrypoint = [ (lib.getExe pkgs.sonarr) ];
      cmd = [
        "-nobrowser"
        "-data=/config"
      ];
      environment.XDG_CONFIG_HOME = "/config";

      dependsOn = [
        "qbittorrent"
        "jackett"
      ];

      volumes = [
        {
          hostPath = baseHDDDir;
          containerPath = "/data";
          customPermissionScript = sharedPermissionScript;
        }
        {
          hostPath = configDir;
          containerPath = "/config";
        }
      ];
    };

    web = {
      port = 8989;
      access = "tailnet";
      probe.path = "/ping";
    };
  };
}
