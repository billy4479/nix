{ pkgs, lib, ... }:
let
  name = "radarr";
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
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        env = [
          "XDG_CONFIG_HOME=/config"
        ];
        entrypoint = [ (lib.getExe pkgs.radarr) ];
        cmd = [
          "-nobrowser"
          "-data=/config"
        ];
      };

      copyToRoot = with pkgs.dockerTools; [
        caCertificates
        (pkgs.writeTextDir "/etc/passwd" "container-5007:x:5007:5000:User for container radarr:/var/empty:/run/current-system/sw/bin/nologin")
      ];
    };
    id = 7;

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
}
