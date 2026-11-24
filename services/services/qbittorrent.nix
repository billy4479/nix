{ pkgs, lib, ... }:
let
  name = "qbittorrent";
  id = 5;
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

  torrentingPort = 6881;
  webUiPort = 8080;
in
{
  polpetta.services.qbittorrent = {
    container = {
      entrypoint = [ (lib.getExe pkgs.qbittorrent-nox) ];

      inherit id;

      environment = {
        HOME = "/config";
        QBT_CONFIRM_LEGAL_NOTICE = "TRUE";
        QBT_PROFILE = "/config";
        QBT_TORRENTING_PORT = toString torrentingPort;
        QBT_WEBUI_PORT = toString webUiPort;
      };

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

      # Resolve trackers through the tunnel too, not via the shared bind9.
      dns = "1.1.1.1";
      extraOptions = [ "--sysctl=net.ipv6.conf.all.disable_ipv6=1" ];
    };

    raw =
      map
        (proto: {
          inherit proto;
          port = torrentingPort;
          access = "public";
        })
        [
          "tcp"
          "udp"
        ];

    web = {
      port = webUiPort;
      access = "admin-only";
      integrationClients = [
        "radarr"
        "sonarr"
      ];
    };
  };
}
