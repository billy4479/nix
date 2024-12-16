{
  pkgs,
  lib,
  extraConfig,
  ...
}:
{
  imports = [
    ./plugins/catppuccin.nix
    ./plugins/telescope.nix
    ./plugins/treesitter.nix
  ];
  programs.neovim = {
    enable = true;
    extraLuaConfig = # lua
      ''
        vim.opt.nu = true
        vim.opt.relativenumber = true

        vim.opt.tabstop = 2
        vim.opt.softtabstop = 2
        vim.opt.shiftwidth = 2
        vim.opt.expandtab = true

        vim.opt.smartindent = true

        vim.opt.wrap = false

        vim.opt.hlsearch = false
        vim.opt.incsearch = true

        vim.opt.termguicolors = true

        vim.opt.scrolloff = 8

        vim.opt.updatetime = 50

        vim.opt.colorcolumn = "100"

        vim.g.mapleader = " "
        vim.keymap.set("i", "<C-c>", "<Esc>")
        vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

        vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
        vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
        vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
        vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

        vim.keymap.set("x", "<leader>p", [["_dP]])
        vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
        vim.keymap.set("n", "<leader>Y", [["+Y]])
        vim.keymap.set({"n", "v"}, "<leader>d", "\"_d")

        vim.api.nvim_create_autocmd('TextYankPost', {
            desc = 'Highlight when yanking (copying) text',
            group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
            callback = function()
              vim.highlight.on_yank()
            end,
        })
      '';
  };
}
