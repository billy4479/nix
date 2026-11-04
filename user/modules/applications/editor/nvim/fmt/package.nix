{
  lib,
  writeText,
  writeShellScriptBin,
  neovim,
}:

# The `nvim-fmt` CLI: formats files exactly like interactive Neovim does, by
# driving the user's own conform.nvim setup headlessly (see ./fmt.lua).
let
  fmtLua = writeText "fmt.lua" (builtins.readFile ./fmt.lua);

  fmtScript = lib.replaceStrings [ "@nvim@" "@lua@" ] [ "${neovim}/bin/nvim" "${fmtLua}" ] (
    builtins.readFile ./fmt.sh
  );
in
writeShellScriptBin "nvim-fmt" fmtScript
