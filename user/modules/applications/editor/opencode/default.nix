{ pkgs, config, ... }:
let

  svelte-ai-tools = pkgs.fetchFromGitHub {
    repo = "ai-tools";
    owner = "sveltejs";
    rev = "svelte-core-bestpractices-v2026.03.12-173239";
    hash = "sha256-VGwI5PEAGpzlSYhx8TFIjbj+EWvfQv7wXFOj9OHVDOs=";
  };

  marimo-pair = pkgs.fetchFromGitHub {
    repo = "marimo-pair";
    owner = "marimo-team";
    rev = "v0.0.15";
    hash = "sha256-04mTX78dmVhyNY3li/tA9Ex/FAmK41E352OOCliPrPA=";
  };

  skills = pkgs.symlinkJoin {
    name = "agents-skills";
    paths = [
      # Generate flowbite-svelte skill from https://flowbite-svelte.com/llms.txt
      ./skills

      "${svelte-ai-tools}/tools/skills"
      "${marimo-pair}/skills"
    ];

    postBuild = # sh
      ''
        rm -rf retro-marimo-pair
      '';
  };

in
{
  home.packages = [ pkgs.opencode ];
  home.file = {
    "${config.xdg.configHome}/opencode" = {
      source = ./config;
      recursive = true;
    };
    "${config.home.homeDirectory}/.agents/skills" = {
      source = skills;
      recursive = true;
    };
  };
}
