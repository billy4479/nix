{ pkgs, hosts }:
let
  inherit (pkgs) lib;
  scriptFiles = lib.concatLists (
    lib.mapAttrsToList (
      host: config:
      lib.concatLists (
        lib.mapAttrsToList (
          name: unit:
          lib.concatMap
            (
              phase:
              let
                script = unit.${phase} or "";
              in
              lib.optional (builtins.isString script && script != "") (
                # Syntax checking must not build every image/compiler referenced in
                # the script. These files are parsed only, never executed or deployed.
                pkgs.writeText "${host}-${name}-${phase}.sh" (builtins.unsafeDiscardStringContext script)
              )
            )
            [
              "script"
              "preStart"
              "postStart"
              "preStop"
              "postStop"
              "reload"
            ]
        ) config.systemd.services
      )
    ) hosts
  );
in
pkgs.runCommand "server-service-shell-syntax-test"
  {
    nativeBuildInputs = [ pkgs.bash ];
  }
  # sh
  ''
    for script in ${lib.escapeShellArgs (map toString scriptFiles)}; do
      bash -n "$script"
    done
    touch "$out"
  ''
