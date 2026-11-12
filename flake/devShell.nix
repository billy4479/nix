{ pkgs }:
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

  ];
}
