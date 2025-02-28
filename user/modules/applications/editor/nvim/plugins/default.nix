{ pkgs, ... }:
{
  imports = [
    ./catppuccin.nix
    ./format.nix
    ./jupyter.nix
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
    {
      plugin = todo-comments-nvim;
      type = "lua";
      config = # lua
        ''
          require("todo-comments").setup({})
        '';
    }
    {
      plugin = rainbow-delimiters-nvim;
      type = "lua";
      config = # lua
        ''
          require("rainbow-delimiters.setup").setup({})
        '';
    }
    {
      plugin = oil-nvim;
      type = "lua";
      config = # lua
        ''
          require("oil").setup({})
          vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
        '';
    }
    {
      plugin = mini-pairs;
      type = "lua";
      config = # lua
        ''
          require("mini.pairs").setup()
        '';
    }
  ];
}
