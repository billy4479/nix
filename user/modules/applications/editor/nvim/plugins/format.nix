{ pkgs, ... }:
{
  programs.neovim.plugins = [
    {
      plugin = pkgs.vimPlugins.conform-nvim;
      type = "lua";
      config = # lua
        ''
          require("conform").setup({
            formatters_by_ft = {
                lua = { "stylua" },
                go = { "gofmt" },
                nix = { "nixfmt" },
                python = { "ruff" },
                rust = { "rustfmt", lsp_format = "fallback" },
                javascript = { "prettierd", "prettier", stop_after_first = true },
              },
          })

          vim.api.nvim_create_autocmd("BufWritePre", {
              pattern = "*",
              callback = function(args)
                -- Disable "format_on_save lsp_fallback" for languages that don't
                -- have a well standardized coding style. You can add additional
                -- languages here or re-enable it for the disabled ones.
                local disable_filetypes = { c = true, cpp = true }
                local lsp_format_opt
                if disable_filetypes[args.buf.filetype] then
                  lsp_format_opt = 'never'
                else
                  lsp_format_opt = 'fallback'
                end
                require("conform").format({ bufnr = args.buf, lsp_format = lsp_format_opt })
              end,
          })

          vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

          vim.keymap.set("n", "<leader>f", function()
              local disable_filetypes = { c = true, cpp = true }
              local lsp_format_opt
              if disable_filetypes[args.buf.filetype] then
                lsp_format_opt = 'never'
              else
                lsp_format_opt = 'fallback'
              end

              require('conform').format { async = true, lsp_format = lsp_format_opt}
            end, {}
          )
        '';
    }
  ];
}
