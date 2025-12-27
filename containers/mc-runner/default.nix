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
  };

  volumes = [
    "${baseDir}/mc-runner.db:/mc-runner.db:rw"
    "${worldDir}:/world:rw"
    "${./config.yml}:/config.yml:ro"
  ];
  adminOnlyDirs = [ baseDir ];
  userDirs = [ worldDir ];
}
