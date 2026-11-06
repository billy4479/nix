{ pkgs, flakeInputs }:
let
  development = import ../services/agent-runtime/development.nix { inherit pkgs flakeInputs; };
in
pkgs.runCommand "agent-browser-test"
  {
    nativeBuildInputs = [ development.agentBrowser ];
  }
  # sh
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    trap 'agent-browser close >/dev/null 2>&1 || true' EXIT
    test -f ${development.agentBrowserSkill}/SKILL.md
    agent-browser skills get core > core.md
    grep -q 'snapshot' core.md

    printf '%s' '<title>Browser test</title><h1>Nix browser</h1><label>Name<input id="name"></label>' > page.html
    agent-browser open "file://$PWD/page.html"
    test "$(agent-browser get title)" = 'Browser test'
    agent-browser snapshot -i > snapshot.txt
    grep -q 'Name' snapshot.txt
    agent-browser fill '#name' Billy
    test "$(agent-browser get value '#name')" = Billy
    agent-browser screenshot "$TMPDIR/page.png"
    test -s "$TMPDIR/page.png"
    agent-browser close
    touch "$out"
  ''
