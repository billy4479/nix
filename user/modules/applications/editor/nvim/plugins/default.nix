{ pkgs, ... }:
{
  imports = [
    ./catppuccin.nix
    ./format.nix
    ./lsp.nix
    ./telescope.nix
    ./treesitter.nix
  ];

  programs.neovim.plugins = with pkgs.vimPlugins; [
    {
      plugin = fidget-nvim;
      type = "lua";
      config = # lua
        ''
          require("fidget").setup({
          	notification = { window = { winblend = 0 } },
          })
        '';
    }
    {
      plugin = gitsigns-nvim;
      type = "lua";
      config = # lua
        ''
          require("gitsigns").setup({})
        '';
    }
  ];
}
