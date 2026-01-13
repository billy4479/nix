{ pkgs, lib, ... }:
let
  name = "sonarr";
  baseHDDDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/${name}";
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
        entrypoint = [ (lib.getExe pkgs.sonarr) ];
        cmd = [
          "-nobrowser"
          "-data=/config"
        ];
      };

      copyToRoot = with pkgs.dockerTools; [
        caCertificates
        (pkgs.writeTextDir "/etc/passwd" "container-5009:x:5009:5000:User for container sonarr:/var/empty:/run/current-system/sw/bin/nologin")
      ];
    };
    id = 9;

    volumes = [
      {
        hostPath = baseHDDDir;
        containerPath = "/data";
        userAccessible = true;
        customPermissionScript = ''
          currentPerm=$(stat -c %u:%g "${baseHDDDir}")
          if [ "$currentPerm" != "5009:5000" ]; then
            echo "Fixing permissions for ${baseHDDDir} (non-recursive)"
            chown 5009:5000 "${baseHDDDir}"
            chmod g+rwX "${baseHDDDir}"
            ${lib.getExe' pkgs.acl "setfacl"} -m d:g:family:rwX,g:family:rwX "${baseHDDDir}"
          fi
        '';
      }
      {
        hostPath = configDir;
        containerPath = "/config";
      }
    ];
  };
}
