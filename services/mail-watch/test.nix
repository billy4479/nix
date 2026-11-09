{ pkgs }:
pkgs.runCommand "mail-watch-tests" { nativeBuildInputs = [ pkgs.python3 ]; } # sh
  ''
    cp ${./mail-watch.py} mail-watch.py
    cp ${./test.py} test.py
    python3 test.py
    touch "$out"
  ''
