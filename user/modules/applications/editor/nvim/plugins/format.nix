{ pkgs, ... }:
{
  programs.neovim = {
    # This shouldn't be necessary,
    # since every project should install it's own formatters in its flake.
    # I leave it here just in case.
    extraPackages = with pkgs; [
    ];

    plugins = [
      {
        plugin = pkgs.vimPlugins.conform-nvim;
        type = "lua";
        config = # lua
          ''
            -- https://github.com/nvim-lua/kickstart.nvim/blob/master/init.lua#L677
            -- https://github.com/tjdevries/config.nvim/blob/master/lua/custom/autoformat.lua
            local conform = require("conform")

            -- Disable logging
            conform.formatters.latexindent = {
            	prepend_args = { "-g", "/dev/null" },
            }

            conform.setup({
            	-- https://github.com/stevearc/conform.nvim?tab=readme-ov-file#formatters
            	formatters_by_ft = {
            		lua = { "stylua" },
            		go = { "gofmt" },
            		nix = { "nixfmt", "injected" },
            		python = { "ruff" },
            		rust = { "rustfmt", lsp_format = "fallback" },
            		javascript = { "prettierd", "prettier", stop_after_first = true },
            		sh = { "shfmt" },
            		tex = { "latexindent" },
            		c = { "clang-format" },
            		cpp = { "clang-format" },
            		-- zig = { "zigfmt" },
            		python = { "ruff_fix", "ruff_organize_imports", "ruff_format" },
            	},

            	formatters = { injected = { options = { ignore_errors = false } } },

            	-- log_level = vim.log.levels.DEBUG,
            })

            local format_buf = function(bufnr, async)
            	-- Disable "format_on_save lsp_fallback" for languages that don't
            	-- have a well standardized coding style. You can add additional
            	-- languages here or re-enable it for the disabled ones.
            	local disable_filetypes = { c = true, cpp = true }
            	local lsp_format_opt
            	if disable_filetypes[vim.bo[bufnr].filetype] then
            		lsp_format_opt = "never"
            	else
            		lsp_format_opt = "fallback"
            	end

            	require("conform").format({
            		async = async,
            		bufnr = bufnr,
            		lsp_format = lsp_format_opt,
            	})
            end

            vim.api.nvim_create_autocmd("BufWritePre", {
            	group = vim.api.nvim_create_augroup("custom-conform", { clear = true }),
            	pattern = "*",
            	callback = function(args)
            		format_buf(args.buf, false)
            	end,
            })

            vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

            vim.keymap.set("n", "<leader>f", function()
            	local bufnr = vim.api.nvim_buf_get_number(0)
            	format_buf(bufnr, true)
            end, {})
          '';
      }
    ];
  };
}
