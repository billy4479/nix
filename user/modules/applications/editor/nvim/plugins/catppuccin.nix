{ pkgs, extraConfig, ... }:
{
  programs.neovim.plugins = with pkgs.vimPlugins; [
    {
      plugin = catppuccin-nvim;
      type = "lua";
      config = # lua
        ''
          require("catppuccin").setup {
                  flavour = "${extraConfig.catppuccinColors.flavor}", 
          }

          vim.cmd.colorscheme "catppuccin"
          vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
          vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
        '';
    }
  ];
}
