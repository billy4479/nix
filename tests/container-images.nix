{ pkgs, serverone }:
let
  inherit (pkgs) lib;
  images = serverone.system.build.containerImages;
  containers = serverone.nerdctl-containers;
  # Exercise a copied executable, a store-only executable, and fixed arguments.
  cases =
    map
      (name: {
        inherit name;
        image = images.${name};
        entrypoint = containers.${name}.entrypoint;
      })
      [
        "certbot"
        "immich-redis"
        "grafana"
      ];
  casesFile = pkgs.writeText "container-image-cases.json" (builtins.toJSON cases);
in
assert lib.all (name: images.${name}.image == "${name}:nix-local") (lib.attrNames containers);
assert containers.immich-redis.copyToRoot == [ ];
assert builtins.length containers.grafana.entrypoint == 2;
assert containers.grafana.cmd == [ "--homepath=${pkgs.grafana}/share/grafana" ];
assert containers.grafana.environment.GF_PATHS_DATA == "/var/lib/grafana";
assert lib.all (
  name:
  let
    command = serverone.systemd.services."nerdctl-${name}".script;
  in
  lib.hasInfix "--snapshotter nix" command
  && lib.hasInfix "--pull never" command
  && !(lib.hasInfix "--entrypoint" command)
) (lib.attrNames containers);
pkgs.runCommand "container-images-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    script = ./container-images.py;
    inherit casesFile;
  }
  # sh
  ''
    python "$script" "$casesFile"
    touch "$out"
  ''
