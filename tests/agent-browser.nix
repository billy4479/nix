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

    # Verify Chromium renders the standard font aliases distinctly, not as one fallback.
    agent-browser eval --stdin <<'JS' > fonts.json
    (() => {
      const ctx = document.createElement('canvas').getContext('2d');
      const measure = (family, text) => {
        ctx.font = '32px "' + family + '"';
        return ctx.measureText(text).width;
      };
      const sample = 'The quick brown fox jumps over the lazy dog';
      return measure('Arial', sample) !== measure('Times New Roman', sample)
        && measure('Courier New', 'iiii') === measure('Courier New', 'WWWW');
    })()
    JS
    grep -qx true fonts.json

    agent-browser screenshot "$TMPDIR/page.png"
    test -s "$TMPDIR/page.png"
    agent-browser close
    touch "$out"
  ''
