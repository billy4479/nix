{ pkgs }:
let
  extensions = import ./extensions { inherit pkgs; };
in
pkgs.runCommand "agent-container-tests"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.nodejs
      pkgs.bash
      pkgs.direnv
    ];
    TEST_PI = "${pkgs.pi-coding-agent}/bin/pi";
    TEST_T3 = "${pkgs.t3code}/bin/t3";
    TEST_OPENCODE = "${pkgs.opencode}/bin/opencode";
    TEST_DIRENV = "${pkgs.direnv}/bin/direnv";
    TEST_BASH = "${pkgs.bash}/bin/bash";
    TEST_EXTENSIONS = extensions;
    TEST_SLEEP = "${pkgs.coreutils}/bin/sleep";
  }
  # sh
  ''
    export HOME="$TMPDIR/home"
    export PYTHONDONTWRITEBYTECODE=1
    mkdir -p "$HOME"
    cp -r ${../agent-config} agent-config
    cp -r ${./.} pi
    chmod -R u+w agent-config pi
    python3 agent-config/test_migrate.py
    python3 agent-config/test_opencode.py
    node --test pi/test.mjs
    python3 pi/test_t3.py
    touch "$out"
  ''
