{ pkgs, lib, ... }:
let
  name = "qbittorrent";
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

  torrentingPort = "6881";
  webUiPort = "8080";
in
{
  nerdctl-containers.${name} = {
    imageToPull = "docker.io/qbittorrentofficial/qbittorrent-nox";
    id = 5;

    environment = {
      "QBT_LEGAL_NOTICE" = "confirm";
      "QBT_TORRENTING_PORT" = torrentingPort;
      "QBT_WEBUI_PORT" = webUiPort;
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

    # Torrenting port is forwarded through WireGuard via vps-proxy,
    # no host port binding needed.
  };
}
