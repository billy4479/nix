{ pkgs, lib, ... }:
let
  name = "radarr";
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
        userAccessible = true;
        customPermissionScript = ''
          currentOwner=$(stat -c %u "${baseHDDDir}")
          currentGroup=$(stat -c %g "${baseHDDDir}")
          if [ "$currentGroup" != "5000" ] || { [ "$currentOwner" != "5007" ] && [ "$currentOwner" != "5009" ]; }; then
            echo "Fixing permissions for ${baseHDDDir} (non-recursive)"
            chown 5007:5000 "${baseHDDDir}"
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
