{ pkgs, ... }:
let
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/syncthing.nix
  # https://github.com/linuxserver/docker-syncthing/blob/master/Dockerfile
  syncthingImage = pkgs.dockerTools.buildImage {
    name = "syncthing";
    tag = "latest";

    runAsRoot = ''
      #!${pkgs.stdenv.shell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r syncthing
      useradd -r -g syncthing -d /data -M syncthing
      mkdir /config
      chown syncthing:syncthing /config
    '';

    copyToRoot = pkgs.buildEnv {
      name = "image-root";
      paths = [ pkgs.syncthing ];
      pathsToLink = [ "/bin" ];
    };

    config = {
      Env = [
        "HOME=/config"
        "STNORESTART=yes"
        "STNOUPGRADE=yes"
      ];

      Volumes = {
        "/config" = { };
      };

      ExposedPorts = {
        "8384" = { };
        "22000/tcp" = { };
        "22000/udp" = { };
        "21027/udp" = { };
      };

      Cmd = [
        "/bin/syncthing"
        "-no-browser"
        "-no-restart"
        "--gui-address=0.0.0.0:8384"
      ];
    };
  };
in
{

  virtualisation.oci-containers.containers = {
    syncthing = {
      autoStart = true;

      # image = "lscr.io/linuxserver/syncthing:latest";
      image = "syncthing:latest";
      imageFile = syncthingImage;
      ports = [
        "127.0.0.1:8384:8384"
        "127.0.0.1:22000:22000/tcp"
        "127.0.0.1:22000:22000/udp"
        "127.0.0.1:21027:21027/udp"
      ];

      volumes = [
        "/mnt/SSD/apps/syncthing/config:/config"
      ];

      extraOptions = [ "--network=host" ];
    };
  };

}
