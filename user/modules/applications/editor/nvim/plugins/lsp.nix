{ pkgs, ... }:
{
  programs.neovim.plugins = with pkgs.vimPlugins; [
    # Truth is, we don't care about who is a dependency of what,
    # we just load everything at the start.
    blink-cmp
    lazydev-nvim
    {
      plugin = nvim-lspconfig;
      type = "lua";
      config = # lua
        ''
          -- https://www.youtube.com/watch?v=bTWWFQZqzyI
          -- https://github.com/nvim-lua/kickstart.nvim/blob/master/init.lua#L455

          local blink = require("blink.cmp")
          blink.setup({})
          local cap = blink.get_lsp_capabilities()
          local lspconfig = require("lspconfig")

          require("lazydev").setup({
          	library = {
          		-- See the configuration section for more details
          		-- Load luvit types when the `vim.uv` word is found

          		-- TODO: I leave this out since the dollar sign has some issues with the nix config
          		-- { path = "{3rd}/luv/library", words = { "vim%.uv" } },
          	},
          })

          local servers = {
          	lua_ls = {},
          	nixd = {},
          	gopls = {},
          }

          for server, config in pairs(servers) do
          	config.capabilities = cap
          	lspconfig[server].setup(config)
          end

          vim.api.nvim_create_autocmd("LspAttach", {
          	group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
          	callback = function(event)
          		-- NOTE: Remember that Lua is a real programming language, and as such it is possible
          		-- to define small helper and utility functions so you don't have to repeat yourself.
          		--
          		-- In this case, we create a function that lets us more easily define mappings specific
          		-- for LSP related items. It sets the mode, buffer and description for us each time.
          		local map = function(keys, func, desc, mode)
          			mode = mode or "n"
          			vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
          		end

          		-- Jump to the definition of the word under your cursor.
          		--  This is where a variable was first declared, or where a function is defined, etc.
          		--  To jump back, press <C-t>.
          		map("gd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")

          		-- Find references for the word under your cursor.
          		map("gr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")

          		-- Jump to the implementation of the word under your cursor.
          		--  Useful when your language has ways of declaring types without an actual implementation.
          		map("gI", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")

          		-- Jump to the type of the word under your cursor.
          		--  Useful when you're not sure what type a variable is and you want to see
          		--  the definition of its *type*, not where it was *defined*.
          		map("<leader>D", require("telescope.builtin").lsp_type_definitions, "Type [D]efinition")

          		-- Fuzzy find all the symbols in your current document.
          		--  Symbols are things like variables, functions, types, etc.
          		map("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")

          		-- Fuzzy find all the symbols in your current workspace.
          		--  Similar to document symbols, except searches over your entire project.
          		map("<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")

          		-- Rename the variable under your cursor.
          		--  Most Language Servers support renaming across files, etc.
          		map("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")

          		-- Execute a code action, usually your cursor needs to be on top of an error
          		-- or a suggestion from your LSP for this to activate.
          		map("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction", { "n", "x" })

          		-- WARN: This is not Goto Definition, this is Goto Declaration.
          		--  For example, in C this would take you to the header.
          		map("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")

          		-- The following two autocommands are used to highlight references of the
          		-- word under your cursor when your cursor rests there for a little while.
          		--    See `:help CursorHold` for information about when this is executed
          		--
          		-- When you move your cursor, the highlights will be cleared (the second autocommand).
          		local client = vim.lsp.get_client_by_id(event.data.client_id)
          		if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
          			local highlight_augroup = vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
          			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
          				buffer = event.buf,
          				group = highlight_augroup,
          				callback = vim.lsp.buf.document_highlight,
          			})

          			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
          				buffer = event.buf,
          				group = highlight_augroup,
          				callback = vim.lsp.buf.clear_references,
          			})

          			vim.api.nvim_create_autocmd("LspDetach", {
          				group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
          				callback = function(event2)
          					vim.lsp.buf.clear_references()
          					vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
          				end,
          			})
          		end

          		-- Toggle inlay hints, enabled by default
          		vim.lsp.inlay_hint.enable(true)
          		if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
          			map("<leader>th", function()
          				vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
          			end, "[T]oggle Inlay [H]ints")
          		end
          	end,
          })
        '';
    }
    {
      plugin = nvim-lint;
      type = "lua";
      config = # lua
        ''
          require("lint").linters_by_ft = {
          	go = { "golangcilint" },
          }

          vim.api.nvim_create_autocmd({ "BufWritePost" }, {
          	group = vim.api.nvim_create_augroup("custom-lint", { clear = true }),
          	callback = function()
          		require("lint").try_lint()
          	end,
          })
        '';
    }
  ];
}
