{ pkgs }:
pkgs.writeShellScriptBin "mail-watch" # sh
  ''
    exec ${pkgs.python3}/bin/python3 ${./mail-watch.py} "$@"
  ''
