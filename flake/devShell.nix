{ pkgs, inputs }:
let
  lazyNixPrefetchDocker =
    pkgs.writeShellScriptBin "nix-prefetch-docker" # sh
      ''
        exec nix run ${inputs.nixpkgs}#nix-prefetch-docker -- "$@"
      '';

  lazyPrefetchAllImages =
    pkgs.writeShellScriptBin "prefetch-all-images" # sh
      ''
        exec ${../packages/prefetch-all-images/prefetch-all-images} "$@"
      '';
in
pkgs.mkShell {
  packages = with pkgs; [
    stylua
    shfmt
    nixfmt
    ruff

    # formatters the nvim conform setup and the nvim-fmt CLI expect for
    # filetypes present in this repo
    jq
    prettier
    rustfmt

    lua-language-server
    nixd

    sops
    age

    dig

    lazyPrefetchAllImages
    lazyNixPrefetchDocker
  ];
}
