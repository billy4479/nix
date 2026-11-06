{ pkgs }:
let
  toml = pkgs.formats.toml { };
  manualConfig = toml.generate "pi-direnv-manual.toml" {
    global.strict_env = true;
  };
  trustedConfig = toml.generate "pi-direnv-trusted.toml" {
    global.strict_env = true;
    whitelist.prefix = [
      "/workspace/code/"
      "/workspace/nix/"
    ];
  };
  configuration =
    pkgs.runCommand "pi-direnv-config" { } # sh
      ''
        mkdir -p "$out/manual" "$out/trusted"
        echo 'source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc' >"$out/manual/direnvrc"
        cp "$out/manual/direnvrc" "$out/trusted/direnvrc"
        cp ${manualConfig} "$out/manual/direnv.toml"
        cp ${trustedConfig} "$out/trusted/direnv.toml"
      '';
in
(pkgs.writeShellScriptBin "direnv" # sh
  ''
    exec ${pkgs.python3}/bin/python3 ${./direnv.py} ${pkgs.direnv}/bin/direnv ${configuration} "$@"
  ''
).overrideAttrs
  (_: {
    passthru = { inherit configuration; };
  })
