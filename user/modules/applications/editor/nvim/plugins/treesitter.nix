{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    extraPackages = with pkgs; [ tree-sitter ];
    plugins = with pkgs.vimPlugins; [
      {
        plugin = (
          nvim-treesitter.withPlugins (
            plugins: with plugins; [
              tree-sitter-bash
              tree-sitter-c
              tree-sitter-cmake
              tree-sitter-cpp
              tree-sitter-css
              tree-sitter-csv
              tree-sitter-dockerfile
              tree-sitter-go
              tree-sitter-html
              tree-sitter-ini
              tree-sitter-javascript
              tree-sitter-json
              tree-sitter-java
              tree-sitter-latex
              tree-sitter-lua
              tree-sitter-make
              tree-sitter-markdown
              tree-sitter-nginx
              tree-sitter-nix
              tree-sitter-python
              tree-sitter-rust
              tree-sitter-svelte
              tree-sitter-templ
              tree-sitter-toml
              tree-sitter-typst
              tree-sitter-typescript
              tree-sitter-yaml
              tree-sitter-zig
            ]
          )
        );
        type = "lua";
        config = # lua
          ''
            require("nvim-treesitter").setup({})

            -- Internal nvim types
            local skip_ft_contains = {
            	"Telescope",
            	"blink",
            	"fidget",
            	"oil",
            }

            local function should_skip(ft)
            	for _, word in ipairs(skip_ft_contains) do
            		if ft:find(word, 1, true) then
            			return true
            		end
            	end
            	return false
            end

            vim.api.nvim_create_autocmd("FileType", {
            	pattern = "*",
            	callback = function()
            		local ft = vim.bo.filetype
            		if ft == "" or should_skip(ft) then
            			return
            		end

            		-- Check if a Tree-sitter parser exists for this filetype
            		local ok = pcall(vim.treesitter.start)
            		if not ok then
            			vim.notify(
            				("Tree-sitter failed to start for filetype: %s"):format(ft),
            				vim.log.levels.WARN,
            				{ title = "Tree-sitter" }
            			)
            			return
            		end

            		-- folds, provided by Neovim
            		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
            		vim.wo.foldmethod = "expr"
            		-- indentation, provided by nvim-treesitter
            		vim.bo.indentexpr = 'v:lua.require("nvim-treesitter").indentexpr()'
            	end,
            })
          '';
      }
    ];
  };
}
