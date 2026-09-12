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
        path = pkgs.lib.makeBinPath (
          with pkgs;
          [
            # mcp-searxng
            searxng-cli
            read-nix-docs
            liteparse
            agent-up

            curl
            diffutils
            fd
            file
            findutils
            gawk
            gh
            git
            gnugrep
            gnumake
            gnused
            gnutar
            gzip
            jq
            p7zip
            poppler-utils
            patch
            procps
            ripgrep
            util-linux
            which
            xz
            zstd

            (python3.withPackages (
              p: with p; [
                numpy
                scipy
                sympy

                pandas
                matplotlib

                pillow

                pypdf

                requests
                beautifulsoup4
              ]
            ))
          ]
        );
      in
      # sh
      ''
        wrapProgram "$out/bin/opencode" \
          --prefix PATH : ${path} \
          --set AGENTUP_URL "https://agent-up.internal.polpetta.online" \
          --set SEARXNG_BASE_URL "https://searxng.internal.polpetta.online" \
          --set SEARXNG_SAFE_SEARCH 0
      '';
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
      "${flakeInputs.read-nix-docs}/skills"
      "${flakeInputs.agent-up}/skills"
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
