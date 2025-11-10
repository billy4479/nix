{ pkgs, config, ... }:
let
  name = "bind9";
  baseDir = "/mnt/SSD/apps/${name}";
  inherit ((import ../utils.nix) { inherit pkgs config; }) makeContainer;

  hosts = pkgs.callPackage ./hosts.nix { };
  bindConfig = pkgs.callPackage ./config.nix { bind9-hosts = hosts; };
in
makeContainer {
  inherit name;
  image = "localhost/bind9:latest";

  ip = "10.0.1.11";
  runByUser = false; # Bind apparently _expects_ to be run as root
  dns = null;

  imageFile =
    with pkgs.dockerTools;
    buildLayeredImage {
      name = "bind9";
      tag = "latest";
      fromImage = pullImage {
        imageName = "ubuntu/bind9";
        imageDigest = "sha256:360622f1481a577822b7a310cdca4e37c16c5d3af53a3e455a13e90cb234943f";
        hash = "sha256-D5w04BL0PzVm2vER+h78bG0mP7ugwxK6kVs9rQUjwhA=";
        finalImageName = "ubuntu/bind9";
        finalImageTag = "latest";
      };

      contents = [ ./contents ];
      config.Entrypoint = [ "/entrypoint.sh" ];
    };

  volumes = [
    "${baseDir}/cache:/var/cache/bind:rw"
    "${baseDir}/lib:/var/lib/bind:rw"
    "${baseDir}/log:/var/log:rw"
    "${bindConfig}:/etc/bind:ro"
  ];
  adminOnlyDirs = [ baseDir ];

  environment = {
    "PUID" = "5000";
    "PGID" = "5000";
  };

  ports = [
    "53:53/tcp"
    "53:53/udp"
  ];
}
