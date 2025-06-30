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
              tree-sitter-kdl
              tree-sitter-latex
              tree-sitter-lua
              tree-sitter-make
              tree-sitter-markdown
              tree-sitter-nix
              tree-sitter-python
              tree-sitter-rust
              tree-sitter-svelte
              tree-sitter-templ
              tree-sitter-typescript
              tree-sitter-yaml
              tree-sitter-zig
            ]
          )
        );
        type = "lua";
        config = # lua
          ''
            require("nvim-treesitter.configs").setup({
            	auto_install = false,

            	highlight = {
            		enable = true,
            		additional_vim_regex_highlighting = false,
            	},
            })
          '';
      }
    ];
  };
}
