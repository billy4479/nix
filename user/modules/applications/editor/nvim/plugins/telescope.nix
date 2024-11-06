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
            require('telescope').setup({})
            local builtin = require('telescope.builtin')

            vim.keymap.set('n', '<leader>pp', builtin.git_files, {})
            vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
            vim.keymap.set('n', '<leader>ps', builtin.live_grep, {})

            vim.keymap.set('n', '<leader>b', builtin.buffers, {})

            -- Search for the word under the cursor
            -- cword : cWORD = w : W
            vim.keymap.set('n', '<leader>pws', function()
              local word = vim.fn.expand("<cword>")
              builtin.grep_string({ search = word })
            end)
            vim.keymap.set('n', '<leader>pWs', function()
              local word = vim.fn.expand("<cWORD>")
              builtin.grep_string({ search = word })
            end)

            vim.keymap.set('n', '<leader>vh', builtin.help_tags, {})          
          '';
      }
    ];
  };
}
