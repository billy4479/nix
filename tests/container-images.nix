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
        absentRootFiles =
          {
            nginx = [ "bin/nginx" ];
            grafana = [ "bin/grafana" ];
            bentopdf = [
              "bin/darkhttpd"
              "share/bentopdf"
            ];
          }
          .${name} or [ ];
      })
      [
        "certbot"
        "immich-redis"
        "grafana"
        "nginx"
        "bentopdf"
      ];
  roots = lib.mapAttrs (
    name: container: pkgs.callPackage ../containers/image-root.nix { inherit name container; }
  ) containers;
  identities = lib.mapAttrsToList (name: container: {
    inherit name;
    root = roots.${name}.identity;
    user = container.userName;
    uid = container.uid;
    home = container.environment.HOME or "/var/empty";
    shell = container.environment.SHELL or "/bin/sh";
  }) containers;
  overlapRoot = pkgs.callPackage ../containers/image-root.nix {
    name = "overlapping-runtime-test";
    container = containers.certbot // {
      copyToRoot = [
        pkgs.bashInteractive
        pkgs.coreutils
      ];
    };
  };
  casesFile = pkgs.writeText "container-image-cases.json" (
    builtins.toJSON {
      images = cases;
      inherit identities;
      gameRuntime = builtins.head containers.game-server-runner.copyToRoot;
      tini = "${pkgs.tini}/bin/tini";
      overlap = {
        root = overlapRoot;
        shell = "${pkgs.bashInteractive}/bin/sh";
      };
    }
  );
in
assert lib.all (name: images.${name}.image == "${name}:nix-local") (lib.attrNames containers);
assert lib.all (name: containers.${name}.copyToRoot == [ ]) [
  "agent-up"
  "bentopdf"
  "calendar-proxy"
  "ff"
  "giuoco-del-divertimento"
  "immich-redis"
  "mircrewrr"
  "nginx"
  "opencloud"
  "quote-bot"
  "searxng"
  "tsidp"
];
assert builtins.length containers.grafana.entrypoint == 2;
assert containers.grafana.cmd == [ "--homepath=${pkgs.grafana}/share/grafana" ];
assert containers.grafana.environment.GF_PATHS_DATA == "/var/lib/grafana";
assert containers.bind9.userName == "bind";
assert containers.postgresql.userName == "postgres";
assert containers.openchamber.userName == "openchamber";
assert containers.t3code.userName == "t3";
# Default store paths must be copied and rooted when a private /nix hides them.
assert lib.all (
  name:
  lib.hasInfix (builtins.unsafeDiscardStringContext (
    toString roots.${name}
  )) serverone.systemd.services."nerdctl-${name}".preStart
) (lib.attrNames (lib.filterAttrs (_: container: container.privateNixStore.enable) containers));
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
