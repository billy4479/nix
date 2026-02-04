{ pkgs, ... }:
{
  imports = [
    ./catppuccin.nix
    ./format.nix
    ./jupyter.nix
    ./lsp.nix
    ./snippets.nix
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
      plugin = multicursors-nvim;
      type = "lua";
      config = # lua
        ''
          require("multicursors").setup({})
          vim.keymap.set({ "v", "n" }, "<leader>m", "<cmd>MCstart<cr>")
        '';
    }
    # {
    #   plugin = mini-pairs;
    #   type = "lua";
    #   config = # lua
    #     ''
    #       require("mini.pairs").setup()
    #     '';
    # }
    {
      plugin = pkgs.vimUtils.buildVimPlugin rec {
        pname = "scroll-eof-nvim";
        version = "1.2.10";
        src = pkgs.fetchFromGitHub {
          owner = "Aasim-A";
          repo = "scrollEOF.nvim";
          rev = version;
          hash = "sha256-hHoS5WgIsbuVEOUbUBpDRxIwdNoR/cAfD+hlBWzaxug=";
        };
      };
      type = "lua";
      config = # lua
        ''
          require("scrollEOF").setup({
          	insert_mode = true,
          })
        '';
    }
    {
      plugin = bufferline-nvim;
      type = "lua";
      config = # lua
        ''
          require("bufferline").setup({})
        '';
    }
    {
      plugin = nvim-origami;
      type = "lua";
      config = # lua
        ''
          vim.opt.foldlevel = 99
          vim.opt.foldlevelstart = 99
          require("origami").setup({})
        '';
    }
  ];
}
