{ pkgs, ... }:
{
  programs.neovim = {
    extraPackages = with pkgs; [
      ripgrep
      fd
      fzf
    ];
    plugins = [
      pkgs.vimPlugins.nvim-web-devicons
      {
        plugin = pkgs.vimPlugins.telescope-nvim;
        type = "lua";
        config = # lua
          ''
            require("telescope").setup({})
            local builtin = require("telescope.builtin")

            vim.keymap.set("n", "<leader><leader>", builtin.git_files, {})
            vim.keymap.set("n", "<leader>f", builtin.find_files, {})
            vim.keymap.set("n", "<leader>s", builtin.live_grep, {})

            vim.keymap.set("n", "<leader>b", builtin.buffers, {})

            -- vim.keymap.set('n', '<leader>pk', builtin.keymaps, {})
            vim.keymap.set("n", "<leader>d", builtin.diagnostics, {})
            -- vim.keymap.set('n', '<leader>ph', builtin.help_tags, {})

            -- Search for the word under the cursor
            -- cword : cWORD = w : W
            -- vim.keymap.set("n", "<leader>pws", function()
            -- 	local word = vim.fn.expand("<cword>")
            -- 	builtin.grep_string({ search = word })
            -- end)
            -- vim.keymap.set("n", "<leader>pWs", function()
            -- 	local word = vim.fn.expand("<cWORD>")
            -- 	builtin.grep_string({ search = word })
            -- end)
          '';
      }
    ];
  };
}
