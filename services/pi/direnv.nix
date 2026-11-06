{ pkgs }:
let
  configuration =
    pkgs.runCommand "pi-direnv-config" { } # sh
      ''
          mkdir -p "$out/manual" "$out/trusted"
          echo 'source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc' > "$out/manual/direnvrc"
          cp "$out/manual/direnvrc" "$out/trusted/direnvrc"
        cat > "$out/manual/direnv.toml" <<'EOF'
        [global]
        strict_env = true
        EOF
        cat > "$out/trusted/direnv.toml" <<'EOF'
        [global]
        strict_env = true
        [whitelist]
          prefix = ["/workspace/code/", "/workspace/nix/"]
          EOF
      '';
in
pkgs.writeShellScriptBin "direnv" # sh
  ''
    exec ${pkgs.python3}/bin/python3 ${./direnv.py} ${pkgs.direnv}/bin/direnv ${configuration} "$@"
  ''
