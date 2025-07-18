{ config, ... }:
{
  imports = [
    ./plugins
  ];

  home.file."${config.xdg.configHome}/nvim/ftplugin".source = ./ftplugin;

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

        vim.opt.scrolloff = 12

        vim.opt.updatetime = 50

        vim.opt.colorcolumn = "100"

        vim.g.mapleader = " "
        vim.keymap.set("i", "<C-c>", "<Esc>")
        vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

        vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
        vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
        vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
        vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

        vim.keymap.set("n", "<leader>c", "<cmd>bd<CR>", { desc = "Close current buffer" })
        vim.keymap.set("n", "<C-Tab>", "<c-6>", { desc = "Cycle last buffer" })
        vim.keymap.set("n", "<leader>n", "<cmd>bnext<CR>", { desc = "Go to next buffer" })
        vim.keymap.set("n", "<leader>p", "<cmd>bprevious<CR>", { desc = "Go to previous buffer" })

        vim.keymap.set("x", "<leader>p", [["_dP]])
        vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
        vim.keymap.set("n", "<leader>Y", [["+Y]])
        vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')

        vim.api.nvim_create_autocmd("TextYankPost", {
        	desc = "Highlight when yanking (copying) text",
        	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
        	callback = function()
        		vim.highlight.on_yank()
        	end,
        })

        vim.api.nvim_create_autocmd("VimEnter", {
        	desc = "Automatically chdir to the command line arg",
        	pattern = "*",
        	group = vim.api.nvim_create_augroup("auto-cmd", { clear = true }),
        	callback = function(arg)
        		local file = string.gsub(arg.file, "oil://", "")
        		if vim.fn.isdirectory(file) == 1 then
        			vim.api.nvim_set_current_dir(file)
        		end
        	end,
        })
      '';
  };
}
