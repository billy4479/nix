{ pkgs, ... }:
let
  websocket-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "websocket-nvim";
    version = "0-unstable-2024-04-14";
    src = pkgs.fetchFromGitHub {
      owner = "AbaoFromCUG";
      repo = "websocket.nvim";
      rev = "8a096d51c957557f939e296c4937f27d5dc596d5";
      hash = "sha256-+Z2RgiqdYWzkEUQRHxqoaiLeekziNaf3bNZEe3dDexI=";
    };
    dependencies = with pkgs.vimPlugins; [
      plenary-nvim
    ];
  };

  neopyter-nvim = pkgs.vimUtils.buildVimPlugin rec {
    pname = "neopyter-nvim";
    version = "0.3.1";
    src = pkgs.fetchFromGitHub {
      owner = "SUSTech-data";
      repo = "neopyter";
      rev = "v${version}";
      hash = "sha256-IW0QjCMQjH2DXBR49T7eUPjdmnjhw4taPBctpSTH2u8=";
    };
    dependencies = with pkgs.vimPlugins; [
      plenary-nvim
      nvim-cmp
      neoconf-nvim
      websocket-nvim
    ];
  };
in
{
  programs.neovim = {
    plugins = with pkgs.vimPlugins; [
      {
        plugin = jupytext-nvim;
        type = "lua";
        config = # lua
          ''
            require("jupytext").setup({
            	-- output_extension = "ju.py",
            })
          '';
      }
      {
        plugin = neopyter-nvim;
        type = "lua";
        config = # lua
          ''
            require("neopyter").setup({})
          '';
      }
    ];
    extraPackages = with pkgs; [
      python3Packages.jupytext
    ];
    extraPython3Packages =
      ps: with ps; [
        pynvim
        jupyter-client
      ];
  };
}
