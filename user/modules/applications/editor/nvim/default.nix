{
  pkgs,
  lib,
  extraConfig,
  ...
}:
{
  imports = [
    ./plugins/catppuccin.nix
    ./plugins/treesitter.nix
  ];
  programs.neovim = {
    enable = true;
    extraLuaConfig = # lua
      ''
        vim.opt.nu = true
        vim.opt.relativenumber = true

        vim.opt.tabstop = 4
        vim.opt.softtabstop = 4
        vim.opt.shiftwidth = 4
        vim.opt.expandtab = true

        vim.opt.smartindent = true

        vim.opt.wrap = false

        vim.opt.hlsearch = false
        vim.opt.incsearch = true

        vim.opt.termguicolors = true

        vim.opt.scrolloff = 8

        vim.opt.updatetime = 50

        -- vim.opt.colorcolumn = "80"

        vim.g.mapleader = " "
        vim.keymap.set("i", "<C-c>", "<Esc>")
        vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)

        vim.keymap.set("x", "<leader>p", [["_dP]])
        vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
        vim.keymap.set("n", "<leader>Y", [["+Y]])
        vim.keymap.set({"n", "v"}, "<leader>d", "\"_d")
      '';
  };
}
