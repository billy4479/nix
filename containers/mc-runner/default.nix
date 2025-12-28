{
  pkgs,
  config,
  extraPkgs,
  ...
}:
let
  inherit ((import ../utils.nix) { inherit pkgs config; }) makeContainer;

  name = "mc-runner";
  baseDir = "/mnt/SSD/apps/${name}";
  worldDir = "/mnt/SSD/minecraft/test-world";
in
makeContainer {
  inherit name;
  image = "localhost/mc-runner:latest";
  imageFile = extraPkgs.my-packages.containers.mc-runner;
  ip = "10.0.1.13";

  environment = {
    DONT_LOAD_DOTENV = "yes";
    PORT = "4479";
    VITE_PORT = "5173";
    ENVIRONMENT = "debug";
    CONFIG_PATH = "/mc-runner/config.yml";
  };

  ports = [
    "25565:25565/tcp"
    "19132:19132/udp"
    "19132:19132/tcp"
  ];

  volumes = [
    "${baseDir}:/mc-runner:rw"
    "${worldDir}:/world:rw"
    "${./config.yml}:/mc-runner/config.yml:ro"
  ];
  adminOnlyDirs = [ baseDir ];
  userDirs = [ worldDir ];
}
