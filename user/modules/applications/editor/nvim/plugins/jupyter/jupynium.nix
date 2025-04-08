{ pkgs, ... }:
let
  version-pioneer = pkgs.python3.pkgs.buildPythonPackage rec {
    pname = "version-pioneer";
    version = "0.0.13";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "kiyoon";
      repo = pname;
      rev = "v${version}";
      hash = "sha256-DYX+VpKXJrKIHcJRMk4ZYgrQXr0181Jsv5eny7yLVpo=";
    };
    build-system = with pkgs.python3Packages; [
      hatchling
      hatch-requirements-txt
      tomli
    ];
  };

  jupynium-ver = "0.2.6";
  jupynium-src = pkgs.fetchFromGitHub {
    owner = "kiyoon";
    repo = "jupynium.nvim";
    rev = "v${jupynium-ver}";
    hash = "sha256-+9J9v+r3fqPWZuQotgzKgqu0/jmviIDeweUUIb4Lxmc=";
  };
  jupynium = pkgs.python3.pkgs.buildPythonPackage {
    pname = "jupynium";
    version = jupynium-ver;
    pyproject = true;

    src = jupynium-src;
    build-system = with pkgs.python3Packages; [
      hatchling
      version-pioneer
      hatch-requirements-txt
    ];

    dependencies = with pkgs.python3Packages; [
      coloredlogs
      gitpython
      persist-queue
      platformdirs
      psutil
      pynvim
      selenium
      verboselogs
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
            require("jupytext").setup({})
          '';
      }
      {
        plugin = pkgs.vimUtils.buildVimPlugin {
          pname = "jupynium-nvim";
          version = "0.2.6";
          src = jupynium-src;
        };
        type = "lua";
        config = # lua
          ''
            require("jupynium").setup({})
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
        jupynium
      ];
  };
}
