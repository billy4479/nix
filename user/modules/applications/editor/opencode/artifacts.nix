{
  pkgs,
  flakeInputs,
}:
let
  package = pkgs.symlinkJoin {
    name = "opencode";
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postBuild =
      let
        path = pkgs.lib.makeBinPath [
          pkgs.mcp-searxng
          pkgs.nix-docs-extractor
        ];
      in
      ''wrapProgram "$out/bin/opencode" --prefix PATH : ${path}'';
  };

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
      ./skills
      "${svelte-ai-tools}/tools/skills"
      "${marimo-pair}/skills"
      "${flakeInputs.nix-docs-extractor}/skills"
    ];

    postBuild = # sh
      ''
        rm -rf retro-marimo-pair
      '';
  };
in
{
  inherit package skills;
  config = ./config;
}
